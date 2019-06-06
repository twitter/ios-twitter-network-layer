//
//  TNLURLSessionManager.m
//  TwitterNetworkLayer
//
//  Created on 10/23/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#include <mach/mach_time.h>
#include <stdatomic.h>

#import "NSCachedURLResponse+TNLAdditions.h"
#import "NSOperationQueue+TNLSafety.h"
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "NSURLSessionTaskMetrics+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLAuthenticationChallengeHandler.h"
#import "TNLBackgroundURLSessionTaskOperationManager.h"
#import "TNLGlobalConfiguration_Project.h"
#import "TNLLRUCache.h"
#import "TNLNetwork.h"
#import "TNLRequestOperation_Project.h"
#import "TNLRequestOperationQueue_Project.h"
#import "TNLTimeoutOperation.h"
#import "TNLTiming.h"
#import "TNLURLSessionManager.h"
#import "TNLURLSessionTaskOperation.h"

NS_ASSUME_NONNULL_BEGIN

@class TNLURLSessionContextLRUCacheDelegate;

#pragma mark - Constants

static const NSUInteger kMaxURLSessionContextCount = 12;

NSTimeInterval TNLGlobalServiceUnavailableRetryAfterBackoffValueDefault = 1.0;
NSTimeInterval TNLGlobalServiceUnavailableRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway = 10.0;

static NSString * const kInAppURLSessionContextIdentifier = @"tnl.op.queue";
static NSString * const kManagerVersionKey = @"smv";

#pragma mark - Static Functions

static NSString *_GenerateReuseIdentifier(NSString * __nullable operationQueueId, NSString *URLSessionConfigurationIdentificationString, TNLRequestExecutionMode executionmode);
static void _ConfigureSessionConfigurationWithRequestConfiguration(NSURLSessionConfiguration * __nullable sessionConfig, TNLRequestConfiguration * requestConfig);
static NSString * __nullable _ServiceUnavailableBackoffKeyFromURL(const TNLGlobalConfigurationServiceUnavailableBackoffMode mode, NSURL *URL);
static void TNLMutableParametersStripNonURLSessionProperties(TNLMutableParameterCollection *params);
static void TNLMutableParametersStripNonBackgroundURLSessionProperties(TNLMutableParameterCollection *params);
static void TNLMutableParametersStripOverriddenURLSessionProperties(TNLMutableParameterCollection *params);

#pragma mark - Global Session Management

static void _PrepareSessionManagement(void);

static dispatch_queue_t sSynchronizeQueue;
static NSOperationQueue *sSynchronizeOperationQueue;
static NSOperationQueue *sURLSessionTaskOperationQueue;
static BOOL sSynchronizeOperationQueueIsBackedBySynchronizeQueue = NO;
static TNLURLSessionContextLRUCacheDelegate *sSessionContextsDelegate;
static TNLLRUCache *sAppSessionContexts;
static TNLLRUCache *sBackgroundSessionContexts;
static NSMutableSet<TNLURLSessionTaskOperation *> *sActiveURLSessionTaskOperations;
static NSMutableDictionary<NSString *, dispatch_block_t> *sBackgroundSessionCompletionHandlerDictionary;
static NSMutableDictionary<NSString *, NSHashTable<NSOperation *> *> *sOutstandingBackoffOperations = nil;
static TNLGlobalConfigurationServiceUnavailableBackoffMode sBackoffMode = TNLGlobalConfigurationServiceUnavailableBackoffModeDisabled;

#pragma mark - Session Context

@interface TNLURLSessionContext : NSObject

@property (nonatomic, readonly) NSURLSession *URLSession;
@property (nonatomic, readonly, copy) NSString *reuseId;
@property (nonatomic, readonly) TNLRequestExecutionMode executionMode;
@property (nonatomic, readonly) NSArray<TNLURLSessionTaskOperation *> *URLSessionTaskOperations;
@property (nonatomic, readonly) uint64_t lastOperationRemovedMachTime;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (NSUInteger)operationCount;
- (void)addOperation:(TNLURLSessionTaskOperation *)op;
- (void)removeOperation:(TNLURLSessionTaskOperation *)op;
- (nullable TNLURLSessionTaskOperation *)operationForTask:(NSURLSessionTask *)task;
- (void)changeOperation:(TNLURLSessionTaskOperation *)op
               fromTask:(NSURLSessionTask *)oldTask
                 toTask:(NSURLSessionTask *)newTask;

@end

@interface TNLURLSessionContext () <TNLLRUEntry>
- (instancetype)initWithURLSession:(NSURLSession *)URLSession
                           reuseId:(NSString *)reuseId
                     executionMode:(TNLRequestExecutionMode)mode NS_DESIGNATED_INITIALIZER;
@end

@interface TNLURLSessionContextLRUCacheDelegate : NSObject <TNLLRUCacheDelegate>
@end

#pragma mark - Session Manager Interfaces

@interface TNLURLSessionManagerV1 : NSObject <TNLURLSessionManager>
+ (instancetype)internalSharedInstance;
@end

@interface TNLURLSessionManagerV1 (Delegate) <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
@end

@interface TNLURLSessionManagerV1 (Synchronize)

// TODO: see if some of these don't actually need a `self` argument

static void _synchronize_findURLSessionTaskOperation(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                     TNLRequestOperationQueue *requestOperationQueue,
                                                     TNLRequestOperation *requestOperation,
                                                     TNLRequestOperationQueueFindTaskOperationCompleteBlock complete);
static NSURLSession *_synchronize_associateTaskOperationWithQueue(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                  TNLURLSessionTaskOperation *taskOperation,
                                                                  TNLRequestOperationQueue *requestOperationQueue,
                                                                  BOOL supportsTaskMetrics);
static void _synchronize_dissassociateURLSessionTaskOperation(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                              TNLURLSessionTaskOperation *op);
static TNLURLSessionContext * __nullable _synchronize_getSessionContextWithQueue(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                                 NSString * __nullable operationQueueId,
                                                                                 TNLRequestConfiguration *requestConfiguration,
                                                                                 TNLRequestExecutionMode executionMode,
                                                                                 BOOL createIfNeeded);
static TNLURLSessionContext * __nullable _synchronize_getSessionContext(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                        NSURLSession *session);
static TNLURLSessionContext * __nullable _synchronize_getSessionContextWithConfigurationIdentifier(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                                                   NSString *identifier);
static void _synchronize_removeContext(PRIVATE_SELF(TNLURLSessionManagerV1),
                                       TNLURLSessionContext *context);
static void _synchronize_storeContext(PRIVATE_SELF(TNLURLSessionManagerV1),
                                      TNLURLSessionContext *context);
static void _synchronize_applyServiceUnavailableBackoffDependencies(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                    NSOperation *op,
                                                                    NSURL *URL,
                                                                    BOOL isLongPoll);
static void _synchronize_serviceUnavailableEncountered(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                       NSURL *URL,
                                                       NSTimeInterval retryAfterDelay);
static void _synchronize_pruneLimit(PRIVATE_SELF(TNLURLSessionManagerV1));
static void _synchronize_pruneUnused(PRIVATE_SELF(TNLURLSessionManagerV1));
static void _synchronize_pruneConfig(PRIVATE_SELF(TNLURLSessionManagerV1),
                                     TNLRequestConfiguration *config,
                                     NSString * __nullable operationQueueId);

static void _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(dispatch_block_t block);

@end

/**
 Subclass TNLURLSessionManagerV1
 Implement URLSession:dataTask:didReceiveResponse:completionHandler:
 Has bugs on older OS versions
 */
@interface TNLURLSessionManagerV2 : TNLURLSessionManagerV1
@end

/**
 Subclass TNLURLSessionManagerV2
 Implement URLSession:task:didFinishCollectingMetrics:
 Has bugs on older OS versions
 */
@interface TNLURLSessionManagerV3 : TNLURLSessionManagerV2
@end

#pragma mark - Implementation

@implementation TNLURLSessionManager

+ (id<TNLURLSessionManager>)sharedInstance
{
    if (![NSURLSessionConfiguration tnl_URLSessionCanReceiveResponseViaDelegate]) {
        return [TNLURLSessionManagerV1 internalSharedInstance];
    } else if (![NSURLSessionConfiguration tnl_URLSessionCanUseTaskTransactionMetrics]) {
        return [TNLURLSessionManagerV2 internalSharedInstance];
    } else {
        return [TNLURLSessionManagerV3 internalSharedInstance];
    }
}

@end

@implementation TNLURLSessionManagerV1

+ (NSInteger)version
{
    return 1;
}

+ (instancetype)internalSharedInstance
{
    static TNLURLSessionManagerV1 *sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[TNLURLSessionManagerV1 alloc] initInternal];
    });
    return sInstance;
}

- (instancetype)initInternal
{
    if (self = [super init]) {
        _PrepareSessionManagement();
    }
    return self;
}

- (void)cancelAllForQueue:(TNLRequestOperationQueue *)queue
                   source:(id<TNLRequestOperationCancelSource>)source
          underlyingError:(nullable NSError *)optionalUnderlyingError
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        NSSet *ops = [sActiveURLSessionTaskOperations copy];
        for (TNLURLSessionTaskOperation *op in ops) {
            if (op.requestOperationQueue == queue) {
                [op cancelWithSource:source underlyingError:optionalUnderlyingError];
            }
        }
    });
}

- (void)findURLSessionTaskOperationForRequestOperationQueue:(TNLRequestOperationQueue *)queue
                                           requestOperation:(TNLRequestOperation *)op
                                                   complete:(TNLRequestOperationQueueFindTaskOperationCompleteBlock)complete
{
    TNLAssert(op.URLSessionTaskOperation == nil);
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        _synchronize_findURLSessionTaskOperation(self,
                                                 queue,
                                                 op,
                                                 complete);
    });
}

- (void)getAllURLSessions:(TNLURLSessionManagerGetAllSessionsCallback)callback
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        NSArray<TNLURLSessionContext *> *foregroundContexts = sAppSessionContexts.allEntries;
        NSArray<TNLURLSessionContext *> *backgroundContexts = sBackgroundSessionContexts.allEntries;
        tnl_dispatch_async_autoreleasing(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSMutableArray<NSURLSession *> *foregroundSessions = [[NSMutableArray alloc] initWithCapacity:foregroundContexts.count];
            NSMutableArray<NSURLSession *> *backgroundSessions = [[NSMutableArray alloc] initWithCapacity:backgroundContexts.count];
            for (TNLURLSessionContext *foregroundContext in foregroundContexts) {
                [foregroundSessions addObject:foregroundContext.URLSession];
            }
            for (TNLURLSessionContext *backgroundContext in backgroundContexts) {
                [backgroundSessions addObject:backgroundContext.URLSession];
            }

            callback(foregroundSessions, backgroundSessions);
        });
    });
}

- (BOOL)handleBackgroundURLSessionEvents:(NSString *)identifier
                       completionHandler:(dispatch_block_t)completionHandler
{
#if !TARGET_OS_IPHONE // == !(IOS + WATCH + TV)
    return NO;
#else
    if (!TNLURLSessionIdentifierIsTaggedForTNL(identifier)) {
        return NO;
    }

    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{

        // TODO:[nobrien] - this JUST handles the background task completing event.
        // Any other events (specifically, auth challenges) are not currently handled.

        TNLURLSessionContext *context = _synchronize_getSessionContextWithConfigurationIdentifier(self, identifier);
        TNLBackgroundURLSessionTaskOperationManager *bgManager = nil;
        if (!context) {
            bgManager = [[TNLBackgroundURLSessionTaskOperationManager alloc] init];
            [bgManager handleBackgroundURLSessionEvents:identifier];
        }

        sBackgroundSessionCompletionHandlerDictionary[identifier] = [^{
            (void)bgManager;
            completionHandler();
        } copy];
    });

    return YES;
#endif // TARGET_OS_IPHONE
}

- (void)URLSessionDidCompleteBackgroundEvents:(NSURLSession *)session
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        NSString *identifier = session.configuration.identifier;
        TNLAssert(identifier != nil);
        if (identifier) {
            dispatch_block_t handler = sBackgroundSessionCompletionHandlerDictionary[identifier];
            [sBackgroundSessionCompletionHandlerDictionary removeObjectForKey:identifier];
            TNLAssert(handler != NULL);
            if (handler) {
                tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), handler);
            }
        }
    });
}

- (void)URLSessionDidCompleteBackgroundTask:(NSUInteger)taskIdentifier
                    sessionConfigIdentifier:(NSString *)sessionConfigIdentifier
                  sharedContainerIdentifier:(nullable NSString *)sharedContainerIdentifier
                                    request:(NSURLRequest *)request
                                   response:(TNLResponse *)response
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        if (sessionConfigIdentifier) {
            userInfo[TNLBackgroundRequestURLSessionConfigurationIdentifierKey] = sessionConfigIdentifier;
        }
        if (response) {
            userInfo[TNLBackgroundRequestResponseKey] = response;
        }
        userInfo[TNLBackgroundRequestURLSessionTaskIdentifierKey] = @(taskIdentifier);
        if (request) {
            userInfo[TNLBackgroundRequestURLRequestKey] = request;
        }
        if (sharedContainerIdentifier) {
            userInfo[TNLBackgroundRequestURLSessionSharedContainerIdentifierKey] = sharedContainerIdentifier;
        }

        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            // notify off the global operation queue's queue
            [[NSNotificationCenter defaultCenter] postNotificationName:TNLBackgroundRequestOperationDidCompleteNotification
                                                                object:nil
                                                              userInfo:userInfo];
        });
    });
}

- (void)syncAddURLSessionTaskOperation:(TNLURLSessionTaskOperation *)op
{
    dispatch_sync(sSynchronizeQueue, ^{
        const NSTimeInterval attemptTimeout = op.requestConfiguration.attemptTimeout;
        const BOOL isLongPollRequest = (attemptTimeout < 1.0) || (attemptTimeout >= NSTimeIntervalSince1970);
        NSURL *URL = op.hydratedURLRequest.URL;
        _synchronize_applyServiceUnavailableBackoffDependencies(self,
                                                                op,
                                                                URL,
                                                                isLongPollRequest);
        [sURLSessionTaskOperationQueue tnl_safeAddOperation:op];
    });
}

- (void)applyServiceUnavailableBackoffDependenciesToOperation:(NSOperation *)op
                                                      withURL:(NSURL *)URL
                                            isLongPollRequest:(BOOL)isLongPoll
{
    dispatch_sync(sSynchronizeQueue, ^{
        _synchronize_applyServiceUnavailableBackoffDependencies(self,
                                                                op,
                                                                URL,
                                                                isLongPoll);
    });
}

- (void)serviceUnavailableEncounteredForURL:(NSURL *)URL
                            retryAfterDelay:(NSTimeInterval)delay
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        _synchronize_serviceUnavailableEncountered(self, URL, delay);
    });
}

- (void)setServiceUnavailableBackoffMode:(TNLGlobalConfigurationServiceUnavailableBackoffMode)mode
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        if (sBackoffMode != mode) {
            sBackoffMode = mode;
            // reset our backoffs
            [sOutstandingBackoffOperations removeAllObjects];
        }
    });
}

- (TNLGlobalConfigurationServiceUnavailableBackoffMode)serviceUnavailableBackoffMode
{
    __block TNLGlobalConfigurationServiceUnavailableBackoffMode mode;
    dispatch_sync(sSynchronizeQueue, ^{
        mode = sBackoffMode;
    });
    return mode;
}

- (void)pruneUnusedURLSessions
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        _synchronize_pruneUnused(self);
    });
}

- (void)pruneURLSessionMatchingRequestConfiguration:(TNLRequestConfiguration *)config
                                   operationQueueId:(nullable NSString *)operationQueueId
{
    config = [config copy]; // force immutable
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        _synchronize_pruneConfig(self, config, operationQueueId);
    });
}

@end

@implementation TNLURLSessionManagerV1 (Synchronize)

static void _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(dispatch_block_t block)
{
    if (dispatch_queue_get_label(sSynchronizeQueue) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)) {
        block();
    } else {
        tnl_dispatch_sync_autoreleasing(sSynchronizeQueue, block);
    }
}

static void _synchronize_findURLSessionTaskOperation(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                     TNLRequestOperationQueue *requestOperationQueue,
                                                     TNLRequestOperation *requestOperation,
                                                     TNLRequestOperationQueueFindTaskOperationCompleteBlock complete)
{
    if (!self) {
        return;
    }

    TNLAssert(requestOperation.URLSessionTaskOperation == nil);
    TNLURLSessionTaskOperation *URLSessionTaskOperation = nil;

    // This NEEDS to be the ONLY place we create a TNLURLSessionTaskOperation.
    URLSessionTaskOperation = [[TNLURLSessionTaskOperation alloc] initWithRequestOperation:requestOperation
                                                                            sessionManager:self];
    NSURLSession *URLSession = _synchronize_associateTaskOperationWithQueue(self,
                                                                            URLSessionTaskOperation,
                                                                            requestOperationQueue,
                                                                            [self respondsToSelector:@selector(URLSession:task:didFinishCollectingMetrics:)]);
    (void)URLSession;
    TNLAssert(URLSession != nil);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
    // Completion block will be cleared when it is called
    URLSessionTaskOperation.completionBlock = ^{
        tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
            _synchronize_dissassociateURLSessionTaskOperation(self, URLSessionTaskOperation);
        });
    };
#pragma clang diagnostic pop

    TNLAssert(URLSessionTaskOperation.URLSession != nil);
    complete(URLSessionTaskOperation);
}

static NSURLSession *_synchronize_associateTaskOperationWithQueue(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                  TNLURLSessionTaskOperation *taskOperation,
                                                                  TNLRequestOperationQueue *requestOperationQueue,
                                                                  BOOL supportsTaskMetrics)
{
    TNLAssert(self);
    if (!self) {
        return nil;
    }

    TNLRequestConfiguration *requestConfig = taskOperation.requestConfiguration;
    TNLRequestExecutionMode mode = taskOperation.executionMode;
    TNLAssert(requestConfig);

    TNLURLSessionContext *context = _synchronize_getSessionContextWithQueue(self,
                                                                            requestOperationQueue.identifier,
                                                                            requestConfig,
                                                                            mode,
                                                                            YES /*createIfNeeded*/);
    TNLAssert(context != nil);
    TNLAssert(context.URLSession != nil);
    [taskOperation setURLSession:context.URLSession supportsTaskMetrics:supportsTaskMetrics];
    [context addOperation:taskOperation];
    [sActiveURLSessionTaskOperations addObject:taskOperation];

    return context.URLSession;
}

static void _synchronize_dissassociateURLSessionTaskOperation(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                              TNLURLSessionTaskOperation *op)
{
    if (!self) {
        return;
    }

    TNLRequestOperationQueue *queue = op.requestOperationQueue;
    TNLRequestConfiguration *requestConfig = op.requestConfiguration;
    TNLRequestExecutionMode mode = op.executionMode;

    TNLAssert(queue);
    TNLAssert(requestConfig);
    if (requestConfig) {
        TNLURLSessionContext *context = _synchronize_getSessionContextWithQueue(self,
                                                                                queue.identifier,
                                                                                requestConfig,
                                                                                mode,
                                                                                NO /*createIfNeeded*/);
        if (context) {
            // remove the operation from the context
            [context removeOperation:op];

            // did the operation fail due to an invalidated NSURLSession?
            const BOOL opHadAnInvalidSession = op.error &&
                                               [op.error.domain isEqualToString:TNLErrorDomain] &&
                                               op.error.code == TNLErrorCodeRequestOperationURLSessionInvalidated;
            if (opHadAnInvalidSession) {

                // was the invalid session the current context object's session?
                if (op.URLSession == context.URLSession) {

                    // context is not longer viable, remove it from our store
                    _synchronize_removeContext(self, context);
                    TNLLogError(@"Encountered invalid NSURLSession, removing from TNL store of sessions");
                }
            }
        }
    }

    // prune
    _synchronize_pruneLimit(self);
    const TNLGlobalConfigurationURLSessionPruneOptions pruneOptions = [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions;
    if (TNL_BITMASK_INTERSECTS_FLAGS(pruneOptions, TNLGlobalConfigurationURLSessionPruneOptionAfterEveryTask)) {
        _synchronize_pruneUnused(self);
    }

    [sActiveURLSessionTaskOperations removeObject:op];
}

static TNLURLSessionContext * __nullable _synchronize_getSessionContextWithQueue(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                                 NSString * __nullable operationQueueId,
                                                                                 TNLRequestConfiguration *requestConfiguration,
                                                                                 TNLRequestExecutionMode executionMode,
                                                                                 BOOL createIfNeeded)
{
    if (!self) {
        return nil;
    }

    TNLAssert(requestConfiguration);


    NSURLCache *canonicalCache = nil;
    NSURLCredentialStorage *canonicalCredentialStorage = nil;
    NSHTTPCookieStorage *canonicalCookieStorage = nil;

    // use demuxers for increased NSURLSession reuse
    canonicalCache = TNLGetURLCacheDemuxProxy();
    canonicalCredentialStorage = TNLGetURLCredentialStorageDemuxProxy();
    canonicalCookieStorage = TNLGetHTTPCookieStorageDemuxProxy();

    TNLMutableParameterCollection *params = TNLMutableParametersFromRequestConfiguration(requestConfiguration,
                                                                                         canonicalCache,
                                                                                         canonicalCredentialStorage,
                                                                                         canonicalCookieStorage);
    if (executionMode != TNLRequestExecutionModeBackground) {
        // Let's aim for higher reusability in our foreground sessions and strip out any information
        // that won't be relevant to identifying the session we wish to access
        TNLMutableParametersStripNonURLSessionProperties(params);
        if (executionMode != TNLRequestExecutionModeBackground) {
            TNLMutableParametersStripNonBackgroundURLSessionProperties(params);
        }
        TNLMutableParametersStripOverriddenURLSessionProperties(params);

        // We DO however need to keep track of our manager version
        params[kManagerVersionKey] = @([[self class] version]);
    }
    NSString *identificationString = [params stableURLEncodedStringValue];
    NSString *reuseId = _GenerateReuseIdentifier(operationQueueId, identificationString, executionMode);
    TNLURLSessionContext *context = _synchronize_getSessionContextWithConfigurationIdentifier(self, reuseId);
    if (!context && createIfNeeded) {
        NSURLSessionConfiguration *canonicalConfiguration;
        canonicalConfiguration = [requestConfiguration generateCanonicalSessionConfigurationWithExecutionMode:executionMode
                                                                                                   identifier:reuseId
                                                                                            canonicalURLCache:canonicalCache
                                                                                canonicalURLCredentialStorage:canonicalCredentialStorage
                                                                                       canonicalCookieStorage:canonicalCookieStorage];
#if DEBUG
        if (TNLRequestExecutionModeBackground == executionMode) {
            TNLAssert([reuseId isEqualToString:canonicalConfiguration.identifier]);
        }
#endif
        NSURLSession *session = [NSURLSession sessionWithConfiguration:canonicalConfiguration
                                                              delegate:self
                                                         delegateQueue:sSynchronizeOperationQueue];

        static volatile atomic_int_fast64_t __attribute__((aligned(8))) sSessionId = 0;
        const int64_t sessionId = atomic_fetch_add(&sSessionId, 1);

        context = [[TNLURLSessionContext alloc] initWithURLSession:session
                                                           reuseId:reuseId
                                                     executionMode:executionMode];
        NSString *sessionDescription = [NSString stringWithFormat:@"%@#%lli", reuseId, sessionId];
        session.sessionDescription = sessionDescription;
        TNLAssert([context.URLSession.sessionDescription isEqualToString:sessionDescription]);
        _synchronize_storeContext(self, context);
    }

    return context;
}

static NSString *_stripSessionIdentifierFromSessionDescription(NSString *sessionDescription)
{
    const NSRange range = [sessionDescription rangeOfString:@"#" options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        return sessionDescription;
    }
    return [sessionDescription substringToIndex:range.location];
}

static TNLURLSessionContext * __nullable _synchronize_getSessionContext(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                        NSURLSession *session)
{
    if (!self) {
        return nil;
    }

    NSString *reuseId = _stripSessionIdentifierFromSessionDescription(session.sessionDescription);
    return _synchronize_getSessionContextWithConfigurationIdentifier(self, reuseId);
}

static TNLURLSessionContext * __nullable _synchronize_getSessionContextWithConfigurationIdentifier(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                                                   NSString *identifier)
{
    if (!self) {
        return nil;
    }

    return [sAppSessionContexts entryWithIdentifier:identifier] ?: [sBackgroundSessionContexts entryWithIdentifier:identifier];
}

static void _synchronize_storeContext(PRIVATE_SELF(TNLURLSessionManagerV1),
                                      TNLURLSessionContext *context)
{
    if (!self) {
        return;
    }

    if (context.executionMode == TNLRequestExecutionModeBackground) {
        [sBackgroundSessionContexts addEntry:context];
        // We don't cap the number of background sessions
    } else {
        [sAppSessionContexts addEntry:context];
        _synchronize_pruneLimit(self);
    }
}

static void _synchronize_removeContext(PRIVATE_SELF(TNLURLSessionManagerV1),
                                       TNLURLSessionContext *context)
{
    if (!self) {
        return;
    }

    if (context.executionMode == TNLRequestExecutionModeBackground) {
        [sBackgroundSessionContexts removeEntry:context];
    } else {
        [sAppSessionContexts removeEntry:context];
    }
}

static void _synchronize_pruneLimit(PRIVATE_SELF(TNLURLSessionManagerV1))
{
    if (!self) {
        return;
    }

    if (sAppSessionContexts.numberOfEntries > kMaxURLSessionContextCount) {

        // Get the least recently used context that doesn't have an associated operation
        TNLURLSessionContext *tail = sAppSessionContexts.tailEntry;
        while (tail && tail.operationCount > 0) {
            tail = tail.previousLRUEntry;
        }

        // If we found an unused context, remove it
        if (tail) {
            [sAppSessionContexts removeEntry:tail];
        }

    }
}

static void _synchronize_pruneUnused(PRIVATE_SELF(TNLURLSessionManagerV1))
{
    if (!self) {
        return;
    }

    // Iterate through all entries (least recent to most recent)
    TNLURLSessionContext *currentEntry = sAppSessionContexts.tailEntry;
    while (currentEntry) {

        TNLURLSessionContext *previous = currentEntry.previousLRUEntry;

        // If the entry doesn't have any operations && hasn't been used recently, remove it
        if (currentEntry.operationCount == 0) {
            const uint64_t lastOperationRemovedMachTime = currentEntry.lastOperationRemovedMachTime;
            if (lastOperationRemovedMachTime > 0) {
                const NSTimeInterval duration = TNLComputeDuration(lastOperationRemovedMachTime, mach_absolute_time());
                if (duration > [TNLGlobalConfiguration sharedInstance].URLSessionInactivityThreshold) {
                    [sAppSessionContexts removeEntry:currentEntry];
                }
            }
        }

        currentEntry = previous;
    }
}

static void _synchronize_pruneConfig(PRIVATE_SELF(TNLURLSessionManagerV1),
                                     TNLRequestConfiguration *config,
                                     NSString * __nullable operationQueueId)
{
    if (!self) {
        return;
    }

    TNLURLSessionContext *context = _synchronize_getSessionContextWithQueue(self,
                                                                            operationQueueId,
                                                                            config,
                                                                            config.executionMode,
                                                                            NO);
    if (context) {
        if (context.operationCount == 0) {
            _synchronize_removeContext(self, context);
        }
    }
}

static void _synchronize_applyServiceUnavailableBackoffDependencies(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                                    NSOperation *op,
                                                                    NSURL *URL,
                                                                    BOOL isLongPoll)
{
    if (!self) {
        return;
    }

    // get the key (depends on the mode)
    NSString *key = _ServiceUnavailableBackoffKeyFromURL(sBackoffMode, URL);
    if (!key) {
        // no key, no dependencies to apply
        return;
    }

    // do we have backoff ops?
    NSHashTable<NSOperation *> *ops = sOutstandingBackoffOperations[key];
    if (!ops) {
        return;
    }

    // we have an in process backoff!
    NSArray<NSOperation *> *opsArray = ops.allObjects;
    if (!opsArray.count) {
        // no backoff ops left, clear it out
        [sOutstandingBackoffOperations removeObjectForKey:key];
        return;
    }

    // make this new operation dependent on prior backoff ops
    for (NSOperation *otherOp in opsArray) {
        [op addDependency:otherOp];
    }

    // store the op if not a long poll request
    if (!isLongPoll) {
        [ops addObject:op];
    }
}

static void _synchronize_serviceUnavailableEncountered(PRIVATE_SELF(TNLURLSessionManagerV1),
                                                       NSURL *URL,
                                                       NSTimeInterval backoffDuration)
{
    if (!self) {
        return;
    }

    if (backoffDuration < 0.1) {
        backoffDuration = 0.1;
    } else if (backoffDuration > TNLGlobalServiceUnavailableRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway) {
        // too long to be treated as a backoff, fall back to the reasonable default
        backoffDuration = TNLGlobalServiceUnavailableRetryAfterBackoffValueDefault;
    }

    NSString *key = _ServiceUnavailableBackoffKeyFromURL(sBackoffMode, URL);
    if (!key) {
        // no key, no backoff to apply
        return;
    }

    NSOperation *timeoutOperation = [[TNLTimeoutOperation alloc] initWithTimeoutDuration:backoffDuration];
    NSHashTable<NSOperation *> *ops = sOutstandingBackoffOperations[key];
    if (!ops) {
        ops = [NSHashTable weakObjectsHashTable];
        sOutstandingBackoffOperations[key] = ops;
    }

    // make all outstanding backed off ops depend on this new backoff op
    for (NSOperation *op in ops.allObjects) {
        [op addDependency:timeoutOperation];
    }

    [ops addObject:timeoutOperation];
    [sURLSessionTaskOperationQueue tnl_safeAddOperation:timeoutOperation];
}

@end

@implementation TNLURLSessionManagerV1 (Delegate)

#pragma mark NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
        didBecomeInvalidWithError:(nullable NSError *)error
{
    METHOD_LOG();

    // TODO: do we need to propogate this event to operations at all?

    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);

        for (TNLURLSessionTaskOperation *op in context.URLSessionTaskOperations) {
            [op URLSession:session didBecomeInvalidWithError:error];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    METHOD_LOG();

    NSMutableArray<id<TNLAuthenticationChallengeHandler>> *handlers = [[[TNLGlobalConfiguration sharedInstance] internalAuthenticationChallengeHandlers] mutableCopy];
    [self private_handleAuthChallenge:challenge
                              session:session
                            operation:nil
                   currentDisposition:nil
       remainingAuthChallengeHandlers:handlers
                           completion:completionHandler];
}

- (void)private_handleAuthChallenge:(NSURLAuthenticationChallenge *)challenge
                            session:(NSURLSession *)session
                          operation:(nullable TNLURLSessionTaskOperation *)operation
                 currentDisposition:(nullable NSNumber *)currentDisposition
     remainingAuthChallengeHandlers:(NSMutableArray<id<TNLAuthenticationChallengeHandler>> *)handlers
                         completion:(TNLURLSessionAuthChallengeCompletionBlock)completion
{
    void (^challengeBlock)(id<TNLAuthenticationChallengeHandler> handler, NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential);
    challengeBlock = ^(id<TNLAuthenticationChallengeHandler> handler, NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential) {
        NSNumber *newDisposition = currentDisposition;
        switch (disposition) {
            case NSURLSessionAuthChallengeUseCredential:
            {
                // There are credentials! Done!
                completion(disposition, credential);
                return;
            }
            case NSURLSessionAuthChallengeCancelAuthenticationChallenge:
            {
                // The challenge is forced to cancel!

                // 1) notify downstream request operations
                if (operation) {
                    // just the provided operation
                    if ((id)[NSNull null] != operation) {
                        [operation handler:handler
          didCancelAuthenticationChallenge:challenge
                             forURLSession:session];
                    }
                } else {
                    // all the downstream operations
                    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
                        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
                        for (TNLURLSessionTaskOperation *op in context.URLSessionTaskOperations) {
                            [op handler:handler
       didCancelAuthenticationChallenge:challenge
                          forURLSession:session];
                        }
                    });
                }

                // 2) complete
                completion(disposition, nil);
                break;
            }
            case NSURLSessionAuthChallengeRejectProtectionSpace:
            {
                // Reject the protection space
                newDisposition = @(disposition);
                break;
            }
            case NSURLSessionAuthChallengePerformDefaultHandling:
            {
                // Leave the disposition as-is (`nil` will be default handling)
                break;
            }
            // default: keep the disposition unchanged
        }
        [self private_handleAuthChallenge:challenge
                                  session:session
                                operation:operation
                       currentDisposition:newDisposition
           remainingAuthChallengeHandlers:handlers
                               completion:completion];
    };

    if (currentDisposition) {
        TNLAssert(currentDisposition.integerValue != NSURLSessionAuthChallengeUseCredential && currentDisposition.integerValue != NSURLSessionAuthChallengeCancelAuthenticationChallenge);
    }

    TNLRequestOperation *requestOp = ((id)[NSNull null] != operation) ? operation.requestOperation : nil;
    while (handlers.count) {
        id<TNLAuthenticationChallengeHandler> handler = handlers.firstObject;
        [handlers removeObjectAtIndex:0];
        if ([handler respondsToSelector:@selector(tnl_networkLayerDidReceiveAuthChallenge:requestOperation:completion:)]) {
            [handler tnl_networkLayerDidReceiveAuthChallenge:challenge
                                            requestOperation:requestOp
                                                  completion:^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential) {
                challengeBlock(handler, disposition, credential);
            }];
            return;
        }
    }

    const NSURLSessionAuthChallengeDisposition finalDisposition = (currentDisposition) ? currentDisposition.integerValue : NSURLSessionAuthChallengePerformDefaultHandling;
    completion(finalDisposition, nil);
}

#if TARGET_OS_IPHONE // == IOS + WATCH + TV
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    [self URLSessionDidCompleteBackgroundEvents:session];
}
#endif

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
        taskIsWaitingForConnectivity:(NSURLSessionTask *)task
{
    METHOD_LOG();
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:task];

        if (op) {
            if (tnl_available_ios_11) {
                [op URLSession:session taskIsWaitingForConnectivity:task];
            }
        }
    });
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
        completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    METHOD_LOG();
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:task];

        if (op) {
            [op URLSession:session
                      task:task
willPerformHTTPRedirection:response
                newRequest:request
         completionHandler:completionHandler];
        } else {
            completionHandler(request);
        }
    });
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * __nullable credential))completionHandler
{
    METHOD_LOG();

    __block TNLURLSessionTaskOperation *op = nil;
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        op = [context operationForTask:task];
    });

    NSMutableArray<id<TNLAuthenticationChallengeHandler>> *handlers = [[[TNLGlobalConfiguration sharedInstance] internalAuthenticationChallengeHandlers] mutableCopy];

    if (op) {
        id<TNLRequestAuthenticationChallengeHandler> delegate = (id)op.requestOperation.requestDelegate;
        if ([delegate respondsToSelector:@selector(tnl_networkLayerDidReceiveAuthChallenge:requestOperation:completion:)]) {
            // delegate is also a challenge handler, give it first change at handling challenge
            if (!handlers) {
                handlers = [[NSMutableArray alloc] init];
            }
            [handlers insertObject:delegate atIndex:0];
        }
    }

    [self private_handleAuthChallenge:challenge
                              session:session
                            operation:op ?: (id)[NSNull null]
                   currentDisposition:nil
       remainingAuthChallengeHandlers:handlers
                           completion:completionHandler];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream * __nullable bodyStream))completionHandler
{
    METHOD_LOG();
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:task];

        if (op) {
            [op URLSession:session
                      task:task
         needNewBodyStream:completionHandler];
        } else {
            completionHandler(nil);
        }
    });
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didSendBodyData:(int64_t)bytesSent
        totalBytesSent:(int64_t)totalBytesSent
        totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:task];

        if (op) {
            [op URLSession:session
                      task:task
           didSendBodyData:bytesSent
            totalBytesSent:totalBytesSent
  totalBytesExpectedToSend:totalBytesExpectedToSend];
        }
        // TODO:[nobrien] - gather heuristics
    });
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didCompleteWithError:(nullable NSError *)error
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:task];

        if (op) {
            [op URLSession:session task:task didCompleteWithError:error];
        }
        // TODO:[nobrien] - gather error info
    });
}

// Not implemented due to crash IOS-31427
// See TNLURLSessionManagerV3
//- (void)URLSession:(NSURLSession *)session
//        task:(NSURLSessionTask *)task
//        didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics;

#pragma mark NSURLSessionDataTaskDelegate

// Not implemented due to IDYN-339, implemented in TNLURLSessionManagerV2
//- (void)URLSession:(NSURLSession *)session
//          dataTask:(NSURLSessionDataTask *)dataTask
//didReceiveResponse:(NSURLResponse *)response
// completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler

// NYI
//- (void)URLSession:(NSURLSession *)session
//        dataTask:(NSURLSessionDataTask *)dataTask
//        didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:dataTask];

        if (op) {
            [op URLSession:session dataTask:dataTask didReceiveData:data];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:dataTask];
        NSCachedURLResponse *flaggedResponse = [proposedResponse tnl_flaggedCachedResponse];

        if (op) {
            [op URLSession:session
                  dataTask:dataTask
         willCacheResponse:flaggedResponse
         completionHandler:completionHandler];
        } else {
            completionHandler(flaggedResponse);
        }
    });
}

#pragma mark NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:downloadTask];

        if (op) {
            [op URLSession:session
              downloadTask:downloadTask
 didFinishDownloadingToURL:location];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
        downloadTask:(NSURLSessionDownloadTask *)downloadTask
        didWriteData:(int64_t)bytesWritten
        totalBytesWritten:(int64_t)totalBytesWritten
        totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:downloadTask];

        if (op) {
            [op URLSession:session
              downloadTask:downloadTask
              didWriteData:bytesWritten
         totalBytesWritten:totalBytesWritten
 totalBytesExpectedToWrite:totalBytesExpectedToWrite];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:downloadTask];

        if (op) {
            [op URLSession:session
              downloadTask:downloadTask
         didResumeAtOffset:fileOffset
        expectedTotalBytes:expectedTotalBytes];
        }
    });
}

@end

static volatile atomic_int_fast32_t sSessionContextCount = ATOMIC_VAR_INIT(0);

@implementation TNLURLSessionContext

@synthesize nextLRUEntry = _nextLRUEntry;
@synthesize previousLRUEntry = _previousLRUEntry;

- (NSString *)LRUEntryIdentifier
{
    return self.reuseId;
}

- (BOOL)shouldAccessMoveLRUEntryToHead
{
    return YES;
}

- (instancetype)initWithURLSession:(NSURLSession *)URLSession
                           reuseId:(NSString *)reuseId
                     executionMode:(TNLRequestExecutionMode)mode
{
    if (self = [super init]) {
        TNLIncrementObjectCount([self class]);

        TNLAssert(reuseId != nil);
        _reuseId = [reuseId copy];
        _URLSession = URLSession;
        _URLSessionTaskOperations = [[NSMutableArray alloc] init];

        const int32_t previousCount = atomic_fetch_add(&sSessionContextCount, 1);
        TNLLogInformation(@"+%@ (%i): %@", NSStringFromClass([self class]), previousCount, reuseId);
        // TNLLogDebug(@"Create %@", _URLSession);
        if (previousCount > 12-1) {
            TNLLogWarning(@"We now have %i %@ instances!", previousCount+1, NSStringFromClass([self class]));
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:TNLNetworkDidSpinUpSessionNotification
                                                            object:nil
                                                          userInfo:@{ TNLNetworkSessionIdentifierKey: _reuseId }];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] postNotificationName:TNLNetworkWillWindDownSessionNotification
                                                        object:nil
                                                      userInfo:@{ TNLNetworkSessionIdentifierKey: _reuseId }];

    const int32_t previousCount = atomic_fetch_sub(&sSessionContextCount, 1);
    TNLLogInformation(@"-%@ (%i): %@", NSStringFromClass([self class]), previousCount, _reuseId);
    // TNLLogDebug(@"Destroy %@", _URLSession);

    TNLURLSessionTaskOperation *op = nil;
    while ((op = _URLSessionTaskOperations.firstObject) != nil) {
        [self removeOperation:op];
    }
    [_URLSession finishTasksAndInvalidate];
    TNLDecrementObjectCount([self class]);
}

- (NSUInteger)operationCount
{
    return _URLSessionTaskOperations.count;
}

- (void)addOperation:(TNLURLSessionTaskOperation *)op
{
    TNLAssert(op);
    TNLAssert([op isKindOfClass:[TNLURLSessionTaskOperation class]]);
    [(NSMutableArray<TNLURLSessionTaskOperation *> *)_URLSessionTaskOperations addObject:op];
    _lastOperationRemovedMachTime = 0;
}

- (void)removeOperation:(TNLURLSessionTaskOperation *)op
{
    NSUInteger idx = [_URLSessionTaskOperations indexOfObject:op];
    if (NSNotFound != idx) {
        [(NSMutableArray<TNLURLSessionTaskOperation *> *)_URLSessionTaskOperations removeObjectAtIndex:idx];
        if (0 == _URLSessionTaskOperations.count) {
            _lastOperationRemovedMachTime = mach_absolute_time();
        }
    }
}

- (nullable TNLURLSessionTaskOperation *)operationForTask:(NSURLSessionTask *)task
{
    TNLAssert(task != nil);
    for (TNLURLSessionTaskOperation *operation in _URLSessionTaskOperations) {
        if (operation.URLSessionTask == task) {
            return operation;
        } else {
            TNLAssert([operation isKindOfClass:[TNLURLSessionTaskOperation class]]);
#if DEBUG
            const NSUInteger taskIdentifier = task.taskIdentifier;
            const NSUInteger opTaskIdentifier = operation.URLSessionTask.taskIdentifier; // not thread safe, thus DEBUG only
            if (taskIdentifier == opTaskIdentifier) {
                if (task != operation.URLSessionTask) {
                    TNLLogError(@"Two tasks with the same identifier for the same session are not the same...?\n\tTask 1: %@ { taskIdentifier: %tu, request: %@ }\n\tTask 2: %@ { taskIdentifier: %tu, request: %@ }", task, taskIdentifier, task.currentRequest, operation.URLSessionTask, opTaskIdentifier, operation.URLSessionTask.currentRequest);
                }
            }
#endif
        }
    }
    return nil;
}

- (void)changeOperation:(TNLURLSessionTaskOperation *)op
               fromTask:(NSURLSessionTask *)oldTask
                 toTask:(NSURLSessionTask *)newTask
{
    TNLAssert(op != nil);
    TNLAssert(oldTask != nil);
    TNLAssert(newTask != nil);
    TNLAssert(oldTask != newTask);
    // TNLAssert(oldTask.taskIdentifier != newTask.taskIdentifier);
}

@end

#pragma mark TNLRequestConfiguration(URLSession)

@implementation TNLRequestConfiguration (URLSession)

+ (TNLRequestConfiguration *)configurationWithSessionConfiguration:(nullable NSURLSessionConfiguration *)sessionConfiguration
{
    return [[self alloc] initWithSessionConfiguration:sessionConfiguration];
}

- (instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)config
{
    if (!config) {
        self = [self init];
    } else if ((self = [super init])) {
        _retryPolicyProvider = nil;
        _URLCredentialStorage = config.URLCredentialStorage;
        _URLCache = config.URLCache;
        _cookieStorage = config.HTTPCookieStorage;
        _sharedContainerIdentifier = [config.sharedContainerIdentifier copy];

        _ivars.executionMode = TNLRequestExecutionModeDefault;
        _ivars.redirectPolicy = TNLRequestRedirectPolicyDefault;
        _ivars.responseDataConsumptionMode = TNLResponseDataConsumptionModeDefault;
        _ivars.protocolOptions = TNLRequestProtocolOptionsDefault;
        _ivars.contributeToExecutingNetworkConnectionsCount = YES;
        _ivars.skipHostSanitization = NO;
        _ivars.responseComputeHashAlgorithm = TNLResponseHashComputeAlgorithmNone;

        [self applyDefaultTimeouts];

        _ivars.cachePolicy = config.requestCachePolicy;
        _ivars.networkServiceType = config.networkServiceType;
        _ivars.cookieAcceptPolicy = config.HTTPCookieAcceptPolicy;
        _ivars.allowsCellularAccess = (config.allowsCellularAccess != NO);
        if (tnl_available_ios_11) {
            _ivars.connectivityOptions = (config.waitsForConnectivity != NO) ? TNLRequestConnectivityOptionWaitForConnectivity : TNLRequestConnectivityOptionsNone;
        } else {
            _ivars.connectivityOptions = TNLRequestConnectivityOptionsNone;
        }
        _ivars.discretionary = (config.isDiscretionary != NO);
        _ivars.shouldSetCookies = (config.HTTPShouldSetCookies != NO);
#if TARGET_OS_IPHONE // == IOS + WATCH + TV
        _ivars.shouldLaunchAppForBackgroundEvents = (config.sessionSendsLaunchEvents != NO);
#endif
#if TARGET_OS_IOS
        if (tnl_available_ios_11) {
            _ivars.multipathServiceType = config.multipathServiceType;
        }
#endif
    }
    return self;
}

- (NSURLSessionConfiguration *)generateCanonicalSessionConfiguration
{
    return [self generateCanonicalSessionConfigurationWithExecutionMode:self.executionMode];
}

- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationForBackgroundModeWithIdentifier:(nullable NSString *)identifier
{
    return [self generateCanonicalSessionConfigurationWithExecutionMode:TNLRequestExecutionModeBackground identifier:identifier];
}

- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode
{
    return [self generateCanonicalSessionConfigurationWithExecutionMode:mode identifier:nil];
}

- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode
                                                                           identifier:(nullable NSString *)identifier
{
    return [self generateCanonicalSessionConfigurationWithExecutionMode:mode
                                                             identifier:identifier
                                                      canonicalURLCache:nil
                                          canonicalURLCredentialStorage:nil
                                                 canonicalCookieStorage:nil];
}

- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode
                                                                           identifier:(nullable NSString *)identifier
                                                                    canonicalURLCache:(nullable NSURLCache *)canonicalCache
                                                        canonicalURLCredentialStorage:(nullable NSURLCredentialStorage *)canonicalCredentialStorage
                                                               canonicalCookieStorage:(nullable NSHTTPCookieStorage *)canonicalCookieStorage
{
    if (TNLRequestExecutionModeBackground == mode) {
        if (!identifier) {
            TNLParameterCollection *params = TNLMutableParametersFromRequestConfiguration(self,
                                                                                          canonicalCache,
                                                                                          canonicalCredentialStorage,
                                                                                          canonicalCookieStorage);
            identifier = params.stableURLEncodedStringValue;
        }
    } else {
        identifier = nil;
    }

    // Generate the config (based on execution mode)
    NSURLSessionConfiguration *config = (TNLRequestExecutionModeBackground == mode) ?
                                            [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:identifier] :
                                            [NSURLSessionConfiguration defaultSessionConfiguration];

    // Apply settings
    [self applySettingsToSessionConfiguration:config];

    // Update the containers

    // URL Cache
    config.URLCache = canonicalCache ?: TNLUnwrappedURLCache(config.URLCache);

    // Credential Storage
    config.URLCredentialStorage = canonicalCredentialStorage ?: TNLUnwrappedURLCredentialStorage(config.URLCredentialStorage);

    // Cookie Storage
    config.HTTPCookieStorage = canonicalCookieStorage ?: TNLUnwrappedCookieStorage(config.HTTPCookieStorage);

    return config;
}

- (void)applySettingsToSessionConfiguration:(nullable NSURLSessionConfiguration *)config
{
    // Transfer configuration

    _ConfigureSessionConfigurationWithRequestConfiguration(config, self);

    /// Overrides -- keep TNLMutableParametersStrip* functions up to date as things change in this method

    // Override the timeouts so that TNL owns the timeouts instead of the NSURLSession

    NSTimeInterval dataTimeout = [TNLGlobalConfiguration sharedInstance].timeoutIntervalBetweenDataTransfer;
    if (dataTimeout <= 0.0) {
        dataTimeout = NSTimeIntervalSince1970;
    }
    config.timeoutIntervalForRequest = dataTimeout;

    if (self.executionMode != TNLRequestExecutionModeBackground) {
        config.timeoutIntervalForResource = NSTimeIntervalSince1970;
    }

    // TNL will control when to fail early if waiting for connectivity

    if (tnl_available_ios_11) {
        config.waitsForConnectivity = YES;
    }

    // TNL will have the NSURLRequest control some configurations,
    // so have them be "unrestricted" on the session.
    // This will further reduce the number of NSURLSession instances TNL needs to spin up.

    // TODO: config.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
    config.allowsCellularAccess = YES;
    config.networkServiceType = NSURLNetworkServiceTypeDefault;
}

@end

@implementation NSURLSessionConfiguration (TNLRequestConfiguration)

+ (NSURLSessionConfiguration *)sessionConfigurationWithConfiguration:(TNLRequestConfiguration *)requestConfig
{
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    if (requestConfig.executionMode == TNLRequestExecutionModeBackground) {
        _ConfigureSessionConfigurationWithRequestConfiguration(sessionConfig, requestConfig);
        TNLParameterCollection *params = TNLMutableParametersFromRequestConfiguration(requestConfig, nil, nil, nil);
        sessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:params.stableURLEncodedStringValue];
    }
    _ConfigureSessionConfigurationWithRequestConfiguration(sessionConfig, requestConfig);
    return sessionConfig;
}

+ (NSURLSessionConfiguration *)tnl_defaultSessionConfigurationWithNilPersistence
{
    NSURLSessionConfiguration *config = [[NSURLSessionConfiguration defaultSessionConfiguration] copy];
#if TARGET_OS_IPHONE // == IOS + WATCH + TV
    config.sessionSendsLaunchEvents = YES;
#endif
    config.URLCache = nil;
    config.URLCredentialStorage = nil;
    config.HTTPCookieStorage = nil;
    config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    config.HTTPShouldSetCookies = NO;
    return config;
}

@end

@implementation TNLURLSessionManagerV2

+ (NSInteger)version
{
    return 2;
}

+ (instancetype)internalSharedInstance
{
    static TNLURLSessionManagerV2 *sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[TNLURLSessionManagerV2 alloc] initInternal];
    });
    return sInstance;
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:dataTask];

        if (op) {
            [op URLSession:session
                  dataTask:dataTask
        didReceiveResponse:response
         completionHandler:completionHandler];
        } else {
            completionHandler(NSURLSessionResponseAllow);
        }
    });
}

@end

@implementation TNLURLSessionManagerV3

+ (NSInteger)version
{
    return 3;
}

+ (instancetype)internalSharedInstance
{
    static TNLURLSessionManagerV3 *sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[TNLURLSessionManagerV3 alloc] initInternal];
    });
    return sInstance;
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = _synchronize_getSessionContext(self, session);
        TNLURLSessionTaskOperation *op = [context operationForTask:task];

        if (op) {
            [op URLSession:session task:task didFinishCollectingMetrics:metrics];
        }
    });
}

@end

@implementation TNLURLSessionContextLRUCacheDelegate

- (void)tnl_cache:(TNLLRUCache *)cache didEvictEntry:(TNLURLSessionContext *)entry
{
    TNLLogInformation(@"Evicted TNLURLSessionContext with identifier: %@", entry.reuseId);
}

@end

#pragma mark Exposed Functions

TNLMutableParameterCollection *TNLMutableParametersFromURLSessionConfiguration(NSURLSessionConfiguration * __nullable config)
{
    if (!config) {
        return nil;
    }

    id tempValue;
    TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] init];

    params[TNLSessionConfigurationPropertyKeyRequestCachePolicy] = @(config.requestCachePolicy);
    params[TNLSessionConfigurationPropertyKeyTimeoutIntervalForRequest] = @(round(config.timeoutIntervalForRequest));
    params[TNLSessionConfigurationPropertyKeyTimeoutIntervalForResource] = @(round(config.timeoutIntervalForResource));
    params[TNLSessionConfigurationPropertyKeyNetworkServiceType] = @(config.networkServiceType);
    params[TNLSessionConfigurationPropertyKeyAllowsCellularAccess] = @(config.allowsCellularAccess);
    params[TNLSessionConfigurationPropertyKeyDiscretionary] = @(config.isDiscretionary);
    if (tnl_available_ios_11) {
        params[TNLSessionConfigurationPropertyKeyWaitsForConnectivity] = @(config.waitsForConnectivity);
    }
#if TARGET_OS_IPHONE // == IOS + WATCH + TV
    params[TNLSessionConfigurationPropertyKeySessionSendsLaunchEvents] = @(config.sessionSendsLaunchEvents);
#endif

    tempValue = config.connectionProxyDictionary;
    if ([(NSDictionary *)tempValue count] > 0) {
        NSString *cpdValue = TNLURLEncodeDictionary((NSDictionary *)tempValue, TNLURLEncodingOptionStableOrder);
        TNLAssert(cpdValue.length > 0);
        params[TNLSessionConfigurationPropertyKeyConnectionProxyDictionary] = cpdValue;
    }

    params[TNLSessionConfigurationPropertyKeyTLSMinimumSupportedProtocol] = @(config.TLSMinimumSupportedProtocol);
    params[TNLSessionConfigurationPropertyKeyTLSMaximumSupportedProtocol] = @(config.TLSMaximumSupportedProtocol);
    params[TNLSessionConfigurationPropertyKeyHTTPShouldUsePipelining] = @(config.HTTPShouldUsePipelining);
    params[TNLSessionConfigurationPropertyKeyHTTPShouldSetCookies] = @(config.HTTPShouldSetCookies);
    params[TNLSessionConfigurationPropertyKeyHTTPCookieAcceptPolicy] = @(config.HTTPCookieAcceptPolicy);

    tempValue = config.HTTPAdditionalHeaders;
    if ([(NSDictionary *)tempValue count] > 0) {
        NSString *headersValue = TNLURLEncodeDictionary((NSDictionary *)tempValue, TNLURLEncodingOptionStableOrder);
        TNLAssert(headersValue);
        params[TNLSessionConfigurationPropertyKeyHTTPAdditionalHeaders] = headersValue;
    }

    params[TNLSessionConfigurationPropertyKeyHTTPMaximumConnectionsPerHost] = @(config.HTTPMaximumConnectionsPerHost);

    tempValue = config.HTTPCookieStorage;
    if (tempValue) {
        params[TNLSessionConfigurationPropertyKeyHTTPCookieStorage] = [NSString stringWithFormat:@"%@_%p", NSStringFromClass([tempValue class]), tempValue];
    }

    tempValue = config.URLCredentialStorage;
    if (tempValue) {
        params[TNLSessionConfigurationPropertyKeyURLCredentialStorage] = [NSString stringWithFormat:@"%@_%p", NSStringFromClass([tempValue class]), tempValue];
    }

    tempValue = config.URLCache;
    if (tempValue) {
        params[TNLSessionConfigurationPropertyKeyURLCache] = [NSString stringWithFormat:@"%@_%p", NSStringFromClass([tempValue class]), tempValue];
    }

    NSArray *protocolClasses = config.protocolClasses;
    if (protocolClasses.count > 0) {
        NSUInteger i = 0;
        for (Class class in protocolClasses) {
            params[[NSString stringWithFormat:@"%@%tu", TNLSessionConfigurationPropertyKeyProtocolClassPrefix, i]] = NSStringFromClass(class);
            i++;
        }
    }

    tempValue = config.sharedContainerIdentifier;
    if (tempValue) {
        params[TNLSessionConfigurationPropertyKeySharedContainerIdentifier] = tempValue;
    }

    return params;
}

static void TNLMutableParametersStripNonURLSessionProperties(TNLMutableParameterCollection *params)
{
    // Only for TNL layer (not NSURLSession)
    params[TNLRequestConfigurationPropertyKeyRedirectPolicy] = nil;
    params[TNLRequestConfigurationPropertyKeyResponseDataConsumptionMode] = nil;
    params[TNLRequestConfigurationPropertyKeyOperationTimeout] = nil;
    params[TNLRequestConfigurationPropertyKeyDeferrableInterval] = nil;
    params[TNLRequestConfigurationPropertyKeyConnectivityOptions] = nil;
}

static void TNLMutableParametersStripNonBackgroundURLSessionProperties(TNLMutableParameterCollection *params)
{
    // Strip properties background NSURLSession only properties
    params[TNLRequestConfigurationPropertyKeyIdleTimeout] = nil;
    params[TNLRequestConfigurationPropertyKeyAttemptTimeout] = nil;
    params[TNLRequestConfigurationPropertyKeyShouldLaunchAppForBackgroundEvents] = nil;
}

static void TNLMutableParametersStripOverriddenURLSessionProperties(TNLMutableParameterCollection *params)
{
    // Strip properties that are overridden in order to coalesce more NSURLSession instances
    // TODO: params[TNLRequestConfigurationPropertyKeyCachePolicy] = nil;
    params[TNLRequestConfigurationPropertyKeyAllowsCellularAccess] = nil;
    params[TNLRequestConfigurationPropertyKeyNetworkServiceType] = nil;
}

BOOL TNLURLSessionIdentifierIsTaggedForTNL(NSString *identifier)
{
    return [identifier hasPrefix:[TNLTwitterNetworkLayerURLScheme stringByAppendingString:@"://"]];
}

#pragma mark Private Functions

static NSString *_GenerateReuseIdentifier(NSString * __nullable operationQueueId,
                                          NSString *URLSessionConfigurationIdentificationString,
                                          TNLRequestExecutionMode executionmode)
{
    NSString *identifier = nil;
    NSString *modeStr = nil;
    switch (executionmode) {
        case TNLRequestExecutionModeInApp:
        case TNLRequestExecutionModeInAppBackgroundTask:
            modeStr = @"InApp";
            identifier = kInAppURLSessionContextIdentifier;
            break;
        case TNLRequestExecutionModeBackground:
            modeStr = @"Background";
            identifier = operationQueueId /* nil is OK */;
            break;
        default:
            break;
    }
    TNLAssert(modeStr);
    TNLAssert(URLSessionConfigurationIdentificationString);

    static NSString *sVersionPath;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sVersionPath = [TNLVersion() stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    });

    NSString *reuseId = [NSString stringWithFormat:@"%@://%@/%@/%@?%@", TNLTwitterNetworkLayerURLScheme, identifier, sVersionPath, modeStr, URLSessionConfigurationIdentificationString];
    return reuseId;
}

static void _ConfigureSessionConfigurationWithRequestConfiguration(NSURLSessionConfiguration * __nullable sessionConfig,
                                                                   TNLRequestConfiguration *requestConfig)
{
    // Transfer
    sessionConfig.allowsCellularAccess = requestConfig.allowsCellularAccess;
    sessionConfig.discretionary = requestConfig.isDiscretionary;
    sessionConfig.networkServiceType = requestConfig.networkServiceType;
    sessionConfig.requestCachePolicy = requestConfig.cachePolicy;
    if (tnl_available_ios_11) {
        const TNLRequestConnectivityOptions connectivityOptions = requestConfig.connectivityOptions;
        if (TNL_BITMASK_INTERSECTS_FLAGS(connectivityOptions, TNLRequestConnectivityOptionWaitForConnectivity)) {
            sessionConfig.waitsForConnectivity = YES;
        } else if (TNL_BITMASK_INTERSECTS_FLAGS(connectivityOptions, TNLRequestConnectivityOptionWaitForConnectivityWhenRetryPolicyProvided) && requestConfig.retryPolicyProvider != nil) {
            sessionConfig.waitsForConnectivity = YES;
        } else {
            sessionConfig.waitsForConnectivity = NO;
        }
    }
#if TARGET_OS_IPHONE // == IOS + WATCH + TV
    sessionConfig.sessionSendsLaunchEvents = requestConfig.shouldLaunchAppForBackgroundEvents;
#endif
    sessionConfig.HTTPCookieAcceptPolicy = requestConfig.cookieAcceptPolicy;
    sessionConfig.HTTPShouldSetCookies = requestConfig.shouldSetCookies;
    sessionConfig.sharedContainerIdentifier = requestConfig.sharedContainerIdentifier;
#if TARGET_OS_IOS
    if (tnl_available_ios_11) {
        sessionConfig.multipathServiceType = requestConfig.multipathServiceType;
    }
#endif

    // Transfer protocols
    NSArray<Class> *additionalClasses = TNLProtocolClassesForProtocolOptions(requestConfig.protocolOptions);
    [sessionConfig tnl_insertProtocolClasses:additionalClasses];

    // Transfer potentially proxied values
    sessionConfig.URLCredentialStorage = TNLUnwrappedURLCredentialStorage(requestConfig.URLCredentialStorage);
    sessionConfig.URLCache = TNLUnwrappedURLCache(requestConfig.URLCache);
    sessionConfig.HTTPCookieStorage = TNLUnwrappedCookieStorage(requestConfig.cookieStorage);

    // Best proxy values
    sessionConfig.timeoutIntervalForRequest = (requestConfig.idleTimeout < MIN_TIMER_INTERVAL) ? NSTimeIntervalSince1970 : requestConfig.idleTimeout;
    sessionConfig.timeoutIntervalForResource = (requestConfig.attemptTimeout < MIN_TIMER_INTERVAL) ? NSTimeIntervalSince1970 : requestConfig.attemptTimeout;
}

static NSString * __nullable _ServiceUnavailableBackoffKeyFromURL(const TNLGlobalConfigurationServiceUnavailableBackoffMode mode,
                                                                  NSURL *URL)
{
    switch (mode) {
        case TNLGlobalConfigurationServiceUnavailableBackoffModeKeyOffHost:
            return [URL.host lowercaseString];
        case TNLGlobalConfigurationServiceUnavailableBackoffModeKeyOffHostAndPath:
        {
            NSString *host = [URL.host lowercaseString];
            NSString *path = [URL.path lowercaseString];
            const BOOL pathPrefixedWithSlash = [path hasPrefix:@"/"];

            if (!host.length) {
                if (!path.length) {
                    return nil;
                }
                return (pathPrefixedWithSlash) ? path : [@"/" stringByAppendingString:path];
            }

            if (!path.length) {
                return host;
            }

            return [NSString stringWithFormat:@"%@%@%@", host, (pathPrefixedWithSlash) ? @"" : @"/", path];
        }
        case TNLGlobalConfigurationServiceUnavailableBackoffModeDisabled:
            return nil;
    }

    TNLAssertNever();
    return nil;
}

static void _PrepareSessionManagement()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        // Threading

        sSynchronizeQueue = dispatch_queue_create("TNLURLSessionManager.synchronize.queue", DISPATCH_QUEUE_SERIAL);
        sSynchronizeOperationQueue = [[NSOperationQueue alloc] init];
        sSynchronizeOperationQueue.name = @"TNLURLSessionManager.synchronize.operation.queue";
        sSynchronizeOperationQueue.maxConcurrentOperationCount = 1;
        if ([sSynchronizeOperationQueue respondsToSelector:@selector(setQualityOfService:)]) {
            sSynchronizeOperationQueue.qualityOfService = (NSQualityOfServiceUtility + NSQualityOfServiceUserInitiated / 2);
        }
        if ([sSynchronizeOperationQueue respondsToSelector:@selector(setUnderlyingQueue:)]) {
            sSynchronizeOperationQueue.underlyingQueue = sSynchronizeQueue;
            sSynchronizeOperationQueueIsBackedBySynchronizeQueue = YES;
        }
        sURLSessionTaskOperationQueue = [[NSOperationQueue alloc] init];
        sURLSessionTaskOperationQueue.name = @"TNLURLSessionManager.task.operation.queue";
        sURLSessionTaskOperationQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
        if ([sURLSessionTaskOperationQueue respondsToSelector:@selector(setQualityOfService:)]) {
            sURLSessionTaskOperationQueue.qualityOfService = (NSQualityOfServiceUtility + NSQualityOfServiceUserInitiated / 2);
        }

        // State

        sOutstandingBackoffOperations = [[NSMutableDictionary alloc] init];
        sSessionContextsDelegate = [[TNLURLSessionContextLRUCacheDelegate alloc] init];
        sAppSessionContexts = [[TNLLRUCache alloc] initWithEntries:nil delegate:sSessionContextsDelegate];
        sBackgroundSessionContexts = [[TNLLRUCache alloc] initWithEntries:nil delegate:sSessionContextsDelegate];
        sActiveURLSessionTaskOperations = [[NSMutableSet alloc] init];
        sBackgroundSessionCompletionHandlerDictionary = [[NSMutableDictionary alloc] init];
    });
}

NS_ASSUME_NONNULL_END

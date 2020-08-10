//
//  TNLURLSessionManager.m
//  TwitterNetworkLayer
//
//  Created on 10/23/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#include <mach/mach_time.h>
#include <stdatomic.h>

#import "NSCachedURLResponse+TNLAdditions.h"
#import "NSDictionary+TNLAdditions.h"
#import "NSURLAuthenticationChallenge+TNLAdditions.h"
#import "NSURLResponse+TNLAdditions.h"
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "NSURLSessionTaskMetrics+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLAuthenticationChallengeHandler.h"
#import "TNLBackgroundURLSessionTaskOperationManager.h"
#import "TNLBackoff.h"
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

static NSString * const kInAppURLSessionContextIdentifier = @"tnl.op.queue";
static NSString * const kManagerVersionKey = @"smv";

#pragma mark - Static Functions

static NSString *_GenerateReuseIdentifier(NSString * __nullable operationQueueId, NSString *URLSessionConfigurationIdentificationString, TNLRequestExecutionMode executionmode);
static void _ConfigureSessionConfigurationWithRequestConfiguration(NSURLSessionConfiguration * __nullable sessionConfig, TNLRequestConfiguration * requestConfig);
static NSString * __nullable _BackoffKeyFromURL(const TNLGlobalConfigurationBackoffMode mode, NSURL *URL, NSString * __nullable host);
static void TNLMutableParametersStripNonURLSessionProperties(TNLMutableParameterCollection *params);
static void TNLMutableParametersStripNonBackgroundURLSessionProperties(TNLMutableParameterCollection *params);
static void TNLMutableParametersStripOverriddenURLSessionProperties(TNLMutableParameterCollection *params);
typedef BOOL (^_FilterBlock)(id obj);
static NSArray *_FilterArray(NSArray *source, _FilterBlock filterBlock);

#pragma mark - Global Session Management

static void _PrepareSessionManagement(void);

static dispatch_queue_t sSynchronizeQueue;
static NSOperationQueue *sSynchronizeOperationQueue;
static NSOperationQueue *sURLSessionTaskOperationQueue;
static TNLURLSessionContextLRUCacheDelegate *sSessionContextsDelegate;
static TNLLRUCache *sAppSessionContexts;
static TNLLRUCache *sBackgroundSessionContexts;
static NSMutableSet<TNLURLSessionTaskOperation *> *sActiveURLSessionTaskOperations;
static NSMutableDictionary<NSString *, dispatch_block_t> *sBackgroundSessionCompletionHandlerDictionary;
static NSMutableDictionary<NSString *, NSHashTable<NSOperation *> *> *sOutstandingBackoffOperations = nil;
static NSMutableDictionary<NSString *, NSHashTable<NSOperation *> *> *sOutstandingSerializeOperations = nil;
static NSTimeInterval sSerialDelayDuration = 0.0;
static TNLGlobalConfigurationBackoffMode sBackoffMode = TNLGlobalConfigurationBackoffModeDisabled;
static id<TNLBackoffBehaviorProvider> sBackoffBehaviorProvider = nil;

#pragma mark - Session Context

TNL_OBJC_FINAL TNL_OBJC_DIRECT_MEMBERS
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

TNL_OBJC_DIRECT_MEMBERS
@interface TNLURLSessionContext () <TNLLRUEntry>
- (instancetype)initWithURLSession:(NSURLSession *)URLSession
                           reuseId:(NSString *)reuseId
                     executionMode:(TNLRequestExecutionMode)mode NS_DESIGNATED_INITIALIZER;
@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLURLSessionContextLRUCacheDelegate : NSObject <TNLLRUCacheDelegate>
@end

#pragma mark - Session Manager Interfaces

@interface TNLURLSessionManagerV1 : NSObject <TNLURLSessionManager>
+ (instancetype)internalSharedInstance;
@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLURLSessionManagerV1 (Delegate) <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLURLSessionManagerV1 (Synchronize)

// TODO: see if some of these don't actually need a `self` argument

- (void)_synchronize_findURLSessionTaskOperationForRequestOperationQueue:(TNLRequestOperationQueue *)requestOperationQueue
                                                        requestOperation:(TNLRequestOperation *)requestOperation
                                                              completion:(TNLRequestOperationQueueFindTaskOperationCompleteBlock)complete;
- (NSURLSession *)_synchronize_associateTaskOperation:(TNLURLSessionTaskOperation *)taskOperation
                                            withQueue:(TNLRequestOperationQueue *)requestOperationQueue
                                  supportsTaskMetrics:(BOOL)supportsTaskMetrics;
- (void)_synchronize_dissassociateTaskOperation:(TNLURLSessionTaskOperation *)op;
- (nullable TNLURLSessionContext *)_synchronize_sessionContextWithQueueId:(nullable NSString *)operationQueueId
                                                     requestConfiguration:(TNLRequestConfiguration *)requestConfiguration
                                                            executionMode:(TNLRequestExecutionMode)executionMode
                                                           createIfNeeded:(BOOL)createIfNeeded;
- (nullable TNLURLSessionContext *)_synchronize_sessionContextFromURLSession:(NSURLSession *)session;
- (nullable TNLURLSessionContext *)_synchronize_sessionContextWithConfigurationIdentifier:(NSString *)identifier;
- (void)_synchronize_removeSessionContext:(TNLURLSessionContext *)context;
- (void)_synchronize_storeSessionContext:(TNLURLSessionContext *)context;

- (void)_synchronize_applyBackoffDependenciesToOperation:(NSOperation *)op
                                             matchingURL:(NSURL *)URL
                                                    host:(nullable NSString *)host
                                              isLongPoll:(BOOL)isLongPoll;
- (void)_synchronize_backoffSignalEncounteredForURL:(NSURL *)URL
                                               host:(nullable NSString *)host
                                            headers:(nullable NSDictionary<NSString *, NSString *> *)headers;
- (void)_synchronize_pruneSessionsToLimit;
- (void)_synchronize_pruneUnusedSessions;
- (void)_synchronize_pruneSessionWithConfig:(TNLRequestConfiguration *)config
                           operationQueueId:(nullable NSString *)operationQueueId;

static void _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(dispatch_block_t block);

@end

/**
 Subclass TNLURLSessionManagerV1
 Implement URLSession:task:didFinishCollectingMetrics:
 Has bugs on older OS versions
 */
@interface TNLURLSessionManagerV2 : TNLURLSessionManagerV1
@end

#pragma mark - Implementation

@implementation TNLURLSessionManager

+ (id<TNLURLSessionManager>)sharedInstance
{
    if (![NSURLSessionConfiguration tnl_URLSessionCanUseTaskTransactionMetrics]) {
        return [TNLURLSessionManagerV1 internalSharedInstance];
    } else {
        return [TNLURLSessionManagerV2 internalSharedInstance];
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
        [self _synchronize_findURLSessionTaskOperationForRequestOperationQueue:queue
                                                              requestOperation:op
                                                                    completion:complete];
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

        TNLURLSessionContext *context = [self _synchronize_sessionContextWithConfigurationIdentifier:identifier];
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
        NSString *host = nil;
        if ([TNLGlobalConfiguration sharedInstance].shouldBackoffUseOriginalRequestHost) {
            host = op.originalURLRequest.URL.host;
        }
        [self _synchronize_applyBackoffDependenciesToOperation:op
                                                   matchingURL:URL
                                                          host:host
                                                    isLongPoll:isLongPollRequest];
        [sURLSessionTaskOperationQueue addOperation:op];
    });
}

- (void)applyBackoffDependenciesToOperation:(NSOperation *)op
                                    withURL:(NSURL *)URL
                                       host:(nullable NSString *)host
                          isLongPollRequest:(BOOL)isLongPoll
{
    dispatch_sync(sSynchronizeQueue, ^{
        [self _synchronize_applyBackoffDependenciesToOperation:op
                                                   matchingURL:URL
                                                          host:host
                                                    isLongPoll:isLongPoll];
    });
}

- (void)backoffSignalEncounteredForURL:(NSURL *)URL
                                  host:(nullable NSString *)host
                   responseHTTPHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        [self _synchronize_backoffSignalEncounteredForURL:URL host:host headers:headers];
    });
}

- (void)setBackoffMode:(TNLGlobalConfigurationBackoffMode)mode
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        if (sBackoffMode != mode) {
            sBackoffMode = mode;
            // reset our backoffs
            [sOutstandingBackoffOperations removeAllObjects];
            [sOutstandingSerializeOperations removeAllObjects];
        }
    });
}

- (TNLGlobalConfigurationBackoffMode)backoffMode
{
    __block TNLGlobalConfigurationBackoffMode mode;
    dispatch_sync(sSynchronizeQueue, ^{
        mode = sBackoffMode;
    });
    return mode;
}

- (void)setBackoffBehaviorProvider:(nullable id<TNLBackoffBehaviorProvider>)provider
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        sBackoffBehaviorProvider = provider ?: [[TNLSimpleBackoffBehaviorProvider alloc] init];
        // does not affect our existing backoffs
    });
}

- (id<TNLBackoffBehaviorProvider>)backoffBehaviorProvider
{
    __block id<TNLBackoffBehaviorProvider> provider;
    dispatch_sync(sSynchronizeQueue, ^{
        provider = sBackoffBehaviorProvider;
    });
    return provider;
}

- (void)pruneUnusedURLSessions
{
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        [self _synchronize_pruneUnusedSessions];
    });
}

- (void)pruneURLSessionMatchingRequestConfiguration:(TNLRequestConfiguration *)config
                                   operationQueueId:(nullable NSString *)operationQueueId
{
    config = [config copy]; // force immutable
    tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
        [self _synchronize_pruneSessionWithConfig:config operationQueueId:operationQueueId];
    });
}

@end

@implementation TNLURLSessionManagerV1 (Synchronize)

static void _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(dispatch_block_t block)
{
    @autoreleasepool {
        if (dispatch_queue_get_label(sSynchronizeQueue) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)) {
            block();
        } else {
            dispatch_sync(sSynchronizeQueue, block);
        }
    }
}

- (void)_synchronize_findURLSessionTaskOperationForRequestOperationQueue:(TNLRequestOperationQueue *)requestOperationQueue
                                                        requestOperation:(TNLRequestOperation *)requestOperation
                                                              completion:(TNLRequestOperationQueueFindTaskOperationCompleteBlock)complete
{
    TNLAssert(requestOperation.URLSessionTaskOperation == nil);
    TNLURLSessionTaskOperation *taskOperation = nil;

    // This NEEDS to be the ONLY place we create a TNLURLSessionTaskOperation.
    taskOperation = [[TNLURLSessionTaskOperation alloc] initWithRequestOperation:requestOperation
                                                                            sessionManager:self];
    NSURLSession *session = [self _synchronize_associateTaskOperation:taskOperation
                                                            withQueue:requestOperationQueue
                                                  supportsTaskMetrics:[self respondsToSelector:@selector(URLSession:task:didFinishCollectingMetrics:)]];
    (void)session;
    TNLAssert(session != nil);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
    // Completion block will be cleared when it is called
    taskOperation.completionBlock = ^{
        tnl_dispatch_async_autoreleasing(sSynchronizeQueue, ^{
            [self _synchronize_dissassociateTaskOperation:taskOperation];
        });
    };
#pragma clang diagnostic pop

    TNLAssert(taskOperation.URLSession != nil);
    complete(taskOperation);
}

- (NSURLSession *)_synchronize_associateTaskOperation:(TNLURLSessionTaskOperation *)taskOperation
                                            withQueue:(TNLRequestOperationQueue *)requestOperationQueue
                                  supportsTaskMetrics:(BOOL)supportsTaskMetrics
{
    TNLRequestConfiguration *requestConfig = taskOperation.requestConfiguration;
    TNLRequestExecutionMode mode = taskOperation.executionMode;
    TNLAssert(requestConfig);

    TNLURLSessionContext *context = [self _synchronize_sessionContextWithQueueId:requestOperationQueue.identifier
                                                            requestConfiguration:requestConfig
                                                                   executionMode:mode
                                                                  createIfNeeded:YES];
    TNLAssert(context != nil);
    TNLAssert(context.URLSession != nil);
    [taskOperation setURLSession:context.URLSession supportsTaskMetrics:supportsTaskMetrics];
    [context addOperation:taskOperation];
    [sActiveURLSessionTaskOperations addObject:taskOperation];

    return context.URLSession;
}

- (void)_synchronize_dissassociateTaskOperation:(TNLURLSessionTaskOperation *)op
{
    TNLRequestOperationQueue *queue = op.requestOperationQueue;
    TNLRequestConfiguration *requestConfig = op.requestConfiguration;
    TNLRequestExecutionMode mode = op.executionMode;

    TNLAssert(queue);
    TNLAssert(requestConfig);
    if (requestConfig) {
        TNLURLSessionContext *context = [self _synchronize_sessionContextWithQueueId:queue.identifier
                                                                requestConfiguration:requestConfig
                                                                       executionMode:mode
                                                                      createIfNeeded:NO];
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
                    [self _synchronize_removeSessionContext:context];
                    TNLLogError(@"Encountered invalid NSURLSession, removing from TNL store of sessions");
                }
            }
        }
    }

    // prune
    [self _synchronize_pruneSessionsToLimit];
    const TNLGlobalConfigurationURLSessionPruneOptions pruneOptions = [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions;
    if (TNL_BITMASK_INTERSECTS_FLAGS(pruneOptions, TNLGlobalConfigurationURLSessionPruneOptionAfterEveryTask)) {
        [self _synchronize_pruneUnusedSessions];
    }

    [sActiveURLSessionTaskOperations removeObject:op];
}

- (nullable TNLURLSessionContext *)_synchronize_sessionContextWithQueueId:(nullable NSString *)operationQueueId
                                                     requestConfiguration:(TNLRequestConfiguration *)requestConfiguration
                                                            executionMode:(TNLRequestExecutionMode)executionMode
                                                           createIfNeeded:(BOOL)createIfNeeded
{
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
    TNLURLSessionContext *context = [self _synchronize_sessionContextWithConfigurationIdentifier:reuseId];
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

        static volatile atomic_int_fast64_t __attribute__((aligned(8))) sSessionId = ATOMIC_VAR_INIT(0);
        const int64_t sessionId = atomic_fetch_add(&sSessionId, 1);

        context = [[TNLURLSessionContext alloc] initWithURLSession:session
                                                           reuseId:reuseId
                                                     executionMode:executionMode];
        NSString *sessionDescription = [NSString stringWithFormat:@"%@#%lli", reuseId, sessionId];
        session.sessionDescription = sessionDescription;
        TNLAssert([context.URLSession.sessionDescription isEqualToString:sessionDescription]);
        [self _synchronize_storeSessionContext:context];
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

- (nullable TNLURLSessionContext *)_synchronize_sessionContextFromURLSession:(NSURLSession *)session
{
    if (!self) {
        return nil;
    }

    NSString *reuseId = _stripSessionIdentifierFromSessionDescription(session.sessionDescription);
    return [self _synchronize_sessionContextWithConfigurationIdentifier:reuseId];
}

- (nullable TNLURLSessionContext *)_synchronize_sessionContextWithConfigurationIdentifier:(NSString *)identifier
{
    return [sAppSessionContexts entryWithIdentifier:identifier] ?: [sBackgroundSessionContexts entryWithIdentifier:identifier];
}

- (void)_synchronize_storeSessionContext:(TNLURLSessionContext *)context
{
    if (context.executionMode == TNLRequestExecutionModeBackground) {
        [sBackgroundSessionContexts addEntry:context];
        // We don't cap the number of background sessions
    } else {
        [sAppSessionContexts addEntry:context];
        [self _synchronize_pruneSessionsToLimit];
    }
}

- (void)_synchronize_removeSessionContext:(TNLURLSessionContext *)context
{
    if (context.executionMode == TNLRequestExecutionModeBackground) {
        [sBackgroundSessionContexts removeEntry:context];
    } else {
        [sAppSessionContexts removeEntry:context];
    }
}

- (void)_synchronize_pruneSessionsToLimit
{
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

- (void)_synchronize_pruneUnusedSessions
{
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

- (void)_synchronize_pruneSessionWithConfig:(TNLRequestConfiguration *)config
                           operationQueueId:(nullable NSString *)operationQueueId
{
    TNLURLSessionContext *context = [self _synchronize_sessionContextWithQueueId:operationQueueId
                                                            requestConfiguration:config
                                                                   executionMode:config.executionMode
                                                                  createIfNeeded:NO];
    if (context) {
        if (context.operationCount == 0) {
            [self _synchronize_removeSessionContext:context];
        }
    }
}

- (void)_synchronize_applyBackoffDependenciesToOperation:(NSOperation *)op
                                             matchingURL:(NSURL *)URL
                                                    host:(nullable NSString *)host
                                              isLongPoll:(BOOL)isLongPoll
{
    // get the key (depends on the mode)
    NSString *key = _BackoffKeyFromURL(sBackoffMode, URL, host);
    if (!key) {
        // no key, no dependencies to apply
        return;
    }

    NSHashTable<NSOperation *> *serialOps = sOutstandingSerializeOperations[key];
    NSArray<NSOperation *> *serialOpsArray = _FilterArray(serialOps.allObjects, ^BOOL(NSOperation * obj){
        return !obj.isFinished;
    });
    if (!serialOpsArray.count) {
        // no serial ops left, clear it
        [sOutstandingSerializeOperations removeObjectForKey:key];
        serialOps = nil;
        serialOpsArray = nil;
    }

    NSHashTable<NSOperation *> *backoffOps = sOutstandingBackoffOperations[key];
    NSArray<NSOperation *> *backoffOpsArray = _FilterArray(backoffOps.allObjects, ^BOOL(NSOperation * obj){
        return !obj.isFinished;
    });
    if (!backoffOpsArray.count) {
        if (!serialOps) {
            // no backoff ops left, clear it
            [sOutstandingBackoffOperations removeObjectForKey:key];
            backoffOps = nil;
            backoffOpsArray = nil;
        } else if (!backoffOps) {
            // serial ops but no backoff ops, establish an empty hash-table to populate
            backoffOps = [NSHashTable weakObjectsHashTable];
            sOutstandingBackoffOperations[key] = backoffOps;
        }
    }

    // No backoff ops or serializing ops to back off with
    if (!serialOps && !backoffOps) {
        return;
    }
    TNLAssert(backoffOps != nil);

    // make this new operation dependent on prior backoff ops
    for (NSOperation *otherOp in backoffOpsArray) {
        [op addDependency:otherOp];
    }

    // add serial delay to slow things down while running serially
    if (sSerialDelayDuration > 0 && serialOps.count > 0) {
        NSOperation *timeoutOperation = [[TNLTimeoutOperation alloc] initWithTimeoutDuration:sSerialDelayDuration];
        for (NSOperation *dep in op.dependencies) {
            [timeoutOperation addDependency:dep];
        }
        [backoffOps addObject:timeoutOperation];
        [sURLSessionTaskOperationQueue addOperation:timeoutOperation];
    }

    // store the op if not a long poll request AND we are still in a serialization mode
    if (!isLongPoll && serialOps.count > 0) {
        [backoffOps addObject:op];
    }
}

- (void)_synchronize_backoffSignalEncounteredForURL:(NSURL *)URL
                                               host:(nullable NSString *)host
                                            headers:(nullable NSDictionary<NSString *, NSString *> *)headers
{
    NSString *key = _BackoffKeyFromURL(sBackoffMode, URL, host);
    if (!key) {
        // no key, no backoff to apply
        return;
    }

    const TNLBackoffBehavior backoffBehavior = [sBackoffBehaviorProvider tnl_backoffBehaviorForURL:URL
                                                                                   responseHeaders:headers];

    if (backoffBehavior.backoffDuration > 0) {
        NSOperation *timeoutOperation = [[TNLTimeoutOperation alloc] initWithTimeoutDuration:backoffBehavior.backoffDuration];
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
        [sURLSessionTaskOperationQueue addOperation:timeoutOperation];

        // also add to the outstanding serialization ops
        NSHashTable<NSOperation *> *serialOps = sOutstandingSerializeOperations[key];
        if (!serialOps) {
            serialOps = [NSHashTable weakObjectsHashTable];
            sOutstandingSerializeOperations[key] = serialOps;
        }
        [serialOps addObject:timeoutOperation];
    }

    if (backoffBehavior.serializeDuration > 0) {
        NSOperation *timeoutOperation = [[TNLTimeoutOperation alloc] initWithTimeoutDuration:backoffBehavior.serializeDuration];
        NSHashTable<NSOperation *> *ops = sOutstandingSerializeOperations[key];
        if (!ops) {
            ops = [NSHashTable weakObjectsHashTable];
            sOutstandingSerializeOperations[key] = ops;
        }

        // track the new serialize timer
        [ops addObject:timeoutOperation];
        [sURLSessionTaskOperationQueue addOperation:timeoutOperation];
    }

    sSerialDelayDuration = backoffBehavior.serialDelayDuration;
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];

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
    [self _private_handleAuthChallenge:challenge
                            URLSession:session
                             operation:nil
                    currentDisposition:nil
                              handlers:handlers
                            completion:completionHandler];
}

- (void)_private_notifyAuthChallengeCanceled:(NSURLAuthenticationChallenge *)challenge
                                  URLSession:(NSURLSession *)session
                                   operation:(nullable TNLURLSessionTaskOperation *)operation
                                     handler:(nullable id<TNLAuthenticationChallengeHandler>)handler
                                     context:(nullable id)cancelContext TNL_OBJC_DIRECT
{
    if (operation) {
        // just the provided operation
         if ((id)[NSNull null] != operation) {
             [operation handler:handler
                        didCancelAuthenticationChallenge:challenge
                        forURLSession:session
                        context:cancelContext];
         }
        return;
    }

     // all the downstream operations
     _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
         TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
         for (TNLURLSessionTaskOperation *op in context.URLSessionTaskOperations) {
             [op handler:handler
                 didCancelAuthenticationChallenge:challenge
                 forURLSession:session
                 context:cancelContext];
         }
     });
}

- (void)_private_handleAuthChallenge:(NSURLAuthenticationChallenge *)challenge
                          URLSession:(NSURLSession *)session
                           operation:(nullable TNLURLSessionTaskOperation *)operation
                  currentDisposition:(nullable NSNumber *)currentDisposition
                            handlers:(NSMutableArray<id<TNLAuthenticationChallengeHandler>> *)handlers
                          completion:(TNLURLSessionAuthChallengeCompletionBlock)completion TNL_OBJC_DIRECT
{
    void (^challengeBlock)(id<TNLAuthenticationChallengeHandler> handler, NSURLSessionAuthChallengeDisposition disposition, id credentialOrContext);
    challengeBlock = ^(id<TNLAuthenticationChallengeHandler> handler, NSURLSessionAuthChallengeDisposition disposition, id credentialOrContext) {
        NSNumber *newDisposition = currentDisposition;
        switch (disposition) {
            case NSURLSessionAuthChallengeUseCredential:
            {
                // There are credentials! Done!
                TNLAssert(!credentialOrContext || [credentialOrContext isKindOfClass:[NSURLCredential class]]);
                completion(disposition, (NSURLCredential *)credentialOrContext);
                return;
            }
            case NSURLSessionAuthChallengeCancelAuthenticationChallenge:
            {
                // The challenge is forced to cancel!

                // 1) notify downstream request operations
                [self _private_notifyAuthChallengeCanceled:challenge
                                                URLSession:session
                                                 operation:operation
                                                   handler:handler
                                                   context:credentialOrContext];

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
        [self _private_handleAuthChallenge:challenge
                                URLSession:session
                                 operation:operation
                        currentDisposition:newDisposition
                                  handlers:handlers
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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

    [self _private_handleAuthChallenge:challenge
                            URLSession:session
                             operation:op ?: (id)[NSNull null]
                    currentDisposition:nil
                              handlers:handlers
                            completion:completionHandler];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream * __nullable bodyStream))completionHandler
{
    METHOD_LOG();
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
        TNLURLSessionTaskOperation *op = [context operationForTask:task];

        if (op) {
            [op URLSession:session task:task didCompleteWithError:error];
        }
        // TODO:[nobrien] - gather error info
    });
}

// Not implemented due to crash IOS-31427
// See TNLURLSessionManagerV2
//- (void)URLSession:(NSURLSession *)session
//        task:(NSURLSessionTask *)task
//        didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics;

#pragma mark NSURLSessionDataTaskDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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

// NYI
//- (void)URLSession:(NSURLSession *)session
//        dataTask:(NSURLSessionDataTask *)dataTask
//        didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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

        memset(&_ivars, 0, sizeof(_ivars)); // prep ivars as all 0

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
        _ivars.connectivityOptions = TNLRequestConnectivityOptionsNone;
        if (tnl_available_ios_11) {
            if ([NSURLSessionConfiguration tnl_URLSessionCanUseWaitsForConnectivity]) {
                if (config.waitsForConnectivity) {
                    _ivars.connectivityOptions = TNLRequestConnectivityOptionWaitForConnectivity;
                }
            } else {
                // waitsForConnectivity bug, leave as .None
                if (config.waitsForConnectivity) {
                    TNL_LOG_WAITS_FOR_CONNECTIVITY_WARNING();
                }
            }
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
        _ivars.shouldUseExtendedBackgroundIdleMode = (config.shouldUseExtendedBackgroundIdleMode != NO);
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
        if ([NSURLSessionConfiguration tnl_URLSessionCanUseWaitsForConnectivity]) {
            config.waitsForConnectivity = YES;
        } else {
            config.waitsForConnectivity = NO; // waitsForConnectivity bug
        }
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
    config.shouldUseExtendedBackgroundIdleMode = NO;
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
        task:(NSURLSessionTask *)task
        didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics
{
    _executeOnSynchronizeGCDQueueFromSynchronizeOperationQueue(^{
        TNLURLSessionContext *context = [self _synchronize_sessionContextFromURLSession:session];
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
    params[TNLSessionConfigurationPropertyKeyShouldUseExtendedBackgroundIdleMode] = @(config.shouldUseExtendedBackgroundIdleMode);

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

static NSArray *_FilterArray(NSArray *source, _FilterBlock filterBlock)
{
    NSMutableIndexSet *set = [[NSMutableIndexSet alloc] init];
    [source enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (filterBlock(obj)) {
            [set addIndex:idx];
        }
    }];

    if (set.count == 0) {
        // no matches
        return nil;
    }

    if (((set.lastIndex - set.firstIndex) + 1) == set.count) {
        // contiguous!

        if (set.firstIndex == 0 && set.lastIndex == (source.count - 1)) {
            // same as source
            return [source copy];
        } else {
            return [source subarrayWithRange:NSMakeRange(set.firstIndex, set.count)];
        }
    }

    // non-contiguous

    NSMutableArray *destination = [[NSMutableArray alloc] initWithCapacity:set.count];
    [source enumerateObjectsAtIndexes:set
                              options:0
                           usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [destination addObject:obj];
    }];
    return [destination copy];
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

        if (![NSURLSessionConfiguration tnl_URLSessionCanUseWaitsForConnectivity]) {
            if (sessionConfig.waitsForConnectivity) {
                TNL_LOG_WAITS_FOR_CONNECTIVITY_WARNING();
                sessionConfig.waitsForConnectivity = NO;
            }
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
    sessionConfig.shouldUseExtendedBackgroundIdleMode = requestConfig.shouldUseExtendedBackgroundIdleMode;

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

static NSString * __nullable _BackoffKeyFromURL(const TNLGlobalConfigurationBackoffMode mode,
                                                NSURL *URL,
                                                NSString * __nullable host)
{
    if (TNLGlobalConfigurationBackoffModeDisabled == mode) {
        // return early to avoid the lowercase string overhead
        return nil;
    }

    if (host) {
        host = host.lowercaseString;
    } else {
        host = URL.host.lowercaseString;
    }

    switch (mode) {
        case TNLGlobalConfigurationBackoffModeKeyOffHost:
            return host;
        case TNLGlobalConfigurationBackoffModeKeyOffHostAndPath:
        {
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
        case TNLGlobalConfigurationBackoffModeDisabled:
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
        sSynchronizeOperationQueue.qualityOfService = (NSQualityOfServiceUtility + NSQualityOfServiceUserInitiated / 2);
        sSynchronizeOperationQueue.underlyingQueue = sSynchronizeQueue;
        sURLSessionTaskOperationQueue = [[NSOperationQueue alloc] init];
        sURLSessionTaskOperationQueue.name = @"TNLURLSessionManager.task.operation.queue";
        sURLSessionTaskOperationQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
        sURLSessionTaskOperationQueue.qualityOfService = (NSQualityOfServiceUtility + NSQualityOfServiceUserInitiated / 2);

        // State

        sOutstandingBackoffOperations = [[NSMutableDictionary alloc] init];
        sOutstandingSerializeOperations = [[NSMutableDictionary alloc] init];
        sSessionContextsDelegate = [[TNLURLSessionContextLRUCacheDelegate alloc] init];
        sAppSessionContexts = [[TNLLRUCache alloc] initWithEntries:nil delegate:sSessionContextsDelegate];
        sBackgroundSessionContexts = [[TNLLRUCache alloc] initWithEntries:nil delegate:sSessionContextsDelegate];
        sActiveURLSessionTaskOperations = [[NSMutableSet alloc] init];
        sBackgroundSessionCompletionHandlerDictionary = [[NSMutableDictionary alloc] init];
        sBackoffBehaviorProvider = [[TNLSimpleBackoffBehaviorProvider alloc] init];
    });
}

NS_ASSUME_NONNULL_END

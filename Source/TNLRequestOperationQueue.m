//
//  TNLRequestOperationQueue.m
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#include <objc/message.h>
#include <stdatomic.h>

#import "NSOperationQueue+TNLSafety.h"
#import "NSURLResponse+TNLAdditions.h"
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLBackgroundURLSessionTaskOperationManager.h"
#import "TNLGlobalConfiguration.h"
#import "TNLNetwork.h"
#import "TNLNetworkObserver.h"
#import "TNLPriority.h"
#import "TNLRequest.h"
#import "TNLRequestAuthorizer.h"
#import "TNLRequestOperation_Project.h"
#import "TNLRequestOperationQueue_Project.h"
#import "TNLResponse.h"
#import "TNLURLSessionTaskOperation.h"

#define SELF_ARG PRIVATE_SELF(TNLRequestOperationQueue)

NS_ASSUME_NONNULL_BEGIN

NSString * const TNLBackgroundRequestOperationDidCompleteNotification = @"TNLBackgroundRequestOperationDidCompleteNotification";
NSString * const TNLBackgroundRequestURLRequestKey = @"URLRequest";
NSString * const TNLBackgroundRequestResponseKey = @"response";
NSString * const TNLBackgroundRequestURLSessionConfigurationIdentifierKey = @"identifier";
NSString * const TNLBackgroundRequestURLSessionTaskIdentifierKey = @"taskIdentifier";
NSString * const TNLBackgroundRequestURLSessionSharedContainerIdentifierKey = @"sharedContainerIdentifier";

static void _GlobalRequestOperationQueueAddOperation(TNLRequestOperation *op);

static volatile atomic_int_fast64_t __attribute__((aligned(8))) sGlobalExecutingConnectionCount = 0;
static NSMapTable<NSString *, TNLRequestOperationQueue *> *sGlobalRequestOperationQueueMapTable = nil;
static NSMutableSet<id<TNLNetworkObserver>> *sGlobalNetworkObservers = nil;
static NSOperationQueue *sGlobalRequestOperationQueue = nil;
static NSHashTable<TNLRequestOperation *> *sGlobalAutoDependencyOperations = nil;

//use NSMutableArray instead of NSMutableOrderedSet as it avoids an expensive class load when accessed during +(void)load,
//which for a collection with only a few elements and a few lookups is a worthwhile tradeoff
static NSMutableArray<id<TNLHTTPHeaderProvider>> *sGlobalHeaderProviders = nil;

static dispatch_queue_t _GlobalOperationQueueQueue(void);
static dispatch_queue_t _GlobalOperationQueueQueue()
{
    static dispatch_queue_t sGlobalOperationQueueQueue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sGlobalOperationQueueQueue = dispatch_queue_create("com.TNL.operation.queue.global.queue", DISPATCH_QUEUE_SERIAL);
    });
    return sGlobalOperationQueueQueue;
}

static void _GlobalEnqueueOperation(NSOperation *op);
static void _GlobalEnqueueOperation(NSOperation *op)
{
    @try {
        [sGlobalRequestOperationQueue tnl_safeAddOperation:op];
    } @catch (NSException *exception) {
        TNLLogError(@"[%@ addOperation:%@] - %@", sGlobalRequestOperationQueue, op, exception);
        @throw exception;
    }
}

static NSArray<TNLRequestOperation *> * __nullable _GlobalAutoDependencyOperations(void);
static NSArray<TNLRequestOperation *> * __nullable _GlobalAutoDependencyOperations()
{
    __block NSArray<TNLRequestOperation *> *ops = nil;
    tnl_dispatch_sync_autoreleasing(_GlobalOperationQueueQueue(), ^{
        ops = [sGlobalAutoDependencyOperations allObjects];
    });
    return ops;
}

static void _GlobalAddAutoDependencyOperation(TNLRequestOperation *op);
static void _GlobalAddAutoDependencyOperation(TNLRequestOperation *op)
{
    tnl_dispatch_async_autoreleasing(_GlobalOperationQueueQueue(), ^{
        [sGlobalAutoDependencyOperations addObject:op];
    });
}

#if 0 // no use case a.t.m.
static void _GlobalRemoveAutoDependencyOperation(TNLRequestOperation *op);
static void _GlobalRemoveAutoDependencyOperation(TNLRequestOperation *op)
{
    tnl_dispatch_async_autoreleasing(_GlobalOperationQueueQueue(), ^{
        [sGlobalAutoDependencyOperations removeObject:op];
    });
}
#endif

static void _GlobalApplyAutoDependenciesToOperation(TNLRequestOperation *op);
static void _GlobalApplyAutoDependenciesToOperation(TNLRequestOperation *op)
{
    const NSInteger dependencyThreshold = (NSInteger)[TNLGlobalConfiguration sharedInstance].operationAutomaticDependencyPriorityThreshold;
    if (dependencyThreshold < NSIntegerMax) {
        if (op.priority > dependencyThreshold) {
            // Auto dependency operation encountered!
            _GlobalAddAutoDependencyOperation(op);
        } else {
            // Add outstanding auto dependency operations as dependencies
            NSArray<TNLRequestOperation *> *autoDependencies = _GlobalAutoDependencyOperations();
            if (autoDependencies.count > 0) {
                TNLLogInformation(@"Marking %@ dependent on %tu higher priority operations", op, autoDependencies.count);
                for (TNLRequestOperation *depOp in autoDependencies) {
                    [op addDependency:depOp];
                }
            }
        }
    }
}

@interface TNLRequestOperationQueue (NSURLSessionDelegate) <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
@end

@interface TNLRequestOperationQueue ()
@property (nonatomic, readonly) dispatch_queue_t sessionStateQueue;
@end

#pragma mark - TNLRequestOperationQueue

@implementation TNLRequestOperationQueue
{
    id<TNLNetworkObserver> _networkObserver;
    NSUInteger _suspendCount;
    NSMutableArray<TNLRequestOperation *> *_stagedRequestOperations;
}

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sGlobalRequestOperationQueueMapTable = [NSMapTable strongToWeakObjectsMapTable];
        sGlobalAutoDependencyOperations = [NSHashTable weakObjectsHashTable];

        sGlobalRequestOperationQueue = [[NSOperationQueue alloc] init];
        sGlobalRequestOperationQueue.name = @"com.TNL.global.request.operation.queue";
        sGlobalRequestOperationQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
        if ([sGlobalRequestOperationQueue respondsToSelector:@selector(setQualityOfService:)]) {
            sGlobalRequestOperationQueue.qualityOfService = (NSQualityOfServiceUtility + NSQualityOfServiceUserInitiated / 2);
        }
    });
}

+ (NSOperationQueue *)globalRequestOperationQueue
{
    return sGlobalRequestOperationQueue;
}

+ (void)addGlobalNetworkObserver:(id<TNLNetworkObserver>)observer
{
    tnl_dispatch_async_autoreleasing(_GlobalOperationQueueQueue(), ^{
        if (!sGlobalNetworkObservers) {
            sGlobalNetworkObservers = [[NSMutableSet alloc] init];
        }
        [sGlobalNetworkObservers addObject:observer];
    });
}

+ (void)removeGlobalNetworkObserver:(id<TNLNetworkObserver>)observer
{
    tnl_dispatch_async_autoreleasing(_GlobalOperationQueueQueue(), ^{
        [sGlobalNetworkObservers removeObject:observer];
    });
}

+ (NSArray<id<TNLNetworkObserver>> *)allGlobalNetworkObservers
{
    __block NSArray<id<TNLNetworkObserver>> *allGlobalNetworkObservers = nil;
    tnl_dispatch_sync_autoreleasing(_GlobalOperationQueueQueue(), ^{
        allGlobalNetworkObservers = [sGlobalNetworkObservers allObjects];
    });
    return allGlobalNetworkObservers;
}

+ (void)addGlobalHeaderProvider:(id<TNLHTTPHeaderProvider>)provider
{
    tnl_dispatch_async_autoreleasing(_GlobalOperationQueueQueue(), ^{
        if (!sGlobalHeaderProviders) {
            sGlobalHeaderProviders = [[NSMutableArray alloc] init];
        }
        // remove then add to make sure provider is the latest
        [sGlobalHeaderProviders removeObject:provider];
        [sGlobalHeaderProviders addObject:provider];
    });
}

+ (void)removeGlobalHeaderProvider:(id<TNLHTTPHeaderProvider>)provider
{
    tnl_dispatch_async_autoreleasing(_GlobalOperationQueueQueue(), ^{
        [sGlobalHeaderProviders removeObject:provider];
    });
}

+ (nullable NSArray<id<TNLHTTPHeaderProvider>> *)allGlobalHeaderProviders
{
    __block NSArray* providers = nil;
    tnl_dispatch_sync_autoreleasing(_GlobalOperationQueueQueue(), ^{
        providers = [sGlobalHeaderProviders copy];
    });
    return providers;
}


- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
    return nil;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if (self = [super init]) {
        TNLIncrementObjectCount([self class]);

        _identifier = [identifier copy];
        NSMutableCharacterSet *hostCharSet = [NSMutableCharacterSet characterSetWithRange:NSMakeRange('a', 'z' - 'a' + 1)];
        [hostCharSet addCharactersInRange:NSMakeRange('A', 'Z' - 'A' + 1)];
        [hostCharSet addCharactersInRange:NSMakeRange('0', '9' - '0' + 1)];
        [hostCharSet addCharactersInRange:NSMakeRange('.', 1)];
        [hostCharSet invert];
        if (_identifier.length == 0 || [_identifier rangeOfCharacterFromSet:hostCharSet].location != NSNotFound) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:[NSString stringWithFormat:@"%@ (%@) must be called with a valid URL host/domain string", NSStringFromClass([self class]), NSStringFromSelector(_cmd)]
                                         userInfo:@{ @"identifier" : (_identifier) ?: [NSNull null] }];
        }

        _sessionStateQueue = dispatch_queue_create([identifier stringByAppendingString:@".operation.queue.state.queue"].UTF8String, DISPATCH_QUEUE_SERIAL);
        _stagedRequestOperations = [[NSMutableArray alloc] init];

        __block BOOL didRegister = NO;
        tnl_dispatch_sync_autoreleasing(_GlobalOperationQueueQueue(), ^{
            didRegister = [sGlobalRequestOperationQueueMapTable objectForKey:self.identifier] == nil;
            if (didRegister) {
                [sGlobalRequestOperationQueueMapTable setObject:self forKey:self.identifier];
            }
        });
        if (!didRegister) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:[NSString stringWithFormat:@"%@ already exists with identifier = '%@'", NSStringFromClass([self class]), _identifier]
                                         userInfo:@{ @"identifier" : _identifier }];
        }
    }
    return self;
}

- (void)dealloc
{
    TNLDecrementObjectCount([self class]);
}

+ (instancetype)defaultOperationQueue
{
    static TNLRequestOperationQueue *sDefaultOperationQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sDefaultOperationQueue = [[self alloc] initWithIdentifier:@"com.twitter.http.operation.queue.default"];
    });
    return sDefaultOperationQueue;
}

#pragma mark Background Events

#if TARGET_OS_IPHONE // == IOS + WATCH + TV
+ (BOOL)handleBackgroundURLSessionEvents:(nullable NSString *)identifier
                       completionHandler:(dispatch_block_t)completionHandler
{
    return [[TNLURLSessionManager sharedInstance] handleBackgroundURLSessionEvents:identifier
                                                                 completionHandler:completionHandler];
}
#endif

#pragma mark Mutable properties

- (void)setNetworkObserver:(nullable id<TNLNetworkObserver>)networkObserver
{
    dispatch_async(_sessionStateQueue, ^{
        self->_networkObserver = networkObserver;
    });
}

- (nullable id<TNLNetworkObserver>)networkObserver
{
    __block id<TNLNetworkObserver> observer;
    dispatch_sync(_sessionStateQueue, ^{
        observer = self->_networkObserver;
    });
    return observer;
}

#pragma mark Suspension

- (void)suspend
{
    if (self == [TNLRequestOperationQueue defaultOperationQueue]) {
        TNLAssertNever();
        return;
    }

    METHOD_LOG();

    dispatch_async(_sessionStateQueue, ^{
        self->_suspendCount++;
    });
}

- (void)resume
{
    if (self == [TNLRequestOperationQueue defaultOperationQueue]) {
        TNLAssertNever();
        return;
    }

    METHOD_LOG();

    tnl_dispatch_async_autoreleasing(_sessionStateQueue, ^{
        if (self->_suspendCount > 0) {
            self->_suspendCount--;
        }
        if (0 == self->_suspendCount) {
            [self->_stagedRequestOperations sortUsingComparator:^NSComparisonResult(TNLRequestOperation *obj1, TNLRequestOperation *obj2) {
                NSOperationQueuePriority priority1 = [obj1 queuePriority];
                NSOperationQueuePriority priority2 = [obj2 queuePriority];

                if (priority1 > priority2) {
                    return NSOrderedAscending;  // highest to lowest
                } else if (priority1 < priority2) {
                    return NSOrderedDescending; // highest to lowest
                }
                return NSOrderedSame;
            }];

            for (TNLRequestOperation *op in self->_stagedRequestOperations) {
                if (!op.isFinished && !op.isExecuting && !op.isCancelled) {
                    _GlobalRequestOperationQueueAddOperation(op);
                }
            }
            [self->_stagedRequestOperations removeAllObjects];
        }
    });
}

#pragma mark Enqueue

- (void)enqueueRequestOperation:(TNLRequestOperation *)op
{
    if (!op) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"TNLRequestOperation argument cannot be nil!"
                                     userInfo:@{ @"operationQueue" : self } ];
    } else if (op.requestOperationQueue != nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"TNLRequestOperation provided was already enqueued!"
                                     userInfo:@{ @"requestOperation" : op, @"operationQueue" : self } ];
    } else {
        [op enqueueToOperationQueue:self];
    }
}

- (TNLRequestOperation *)enqueueRequest:(nullable id<TNLRequest>)request
                             completion:(nullable TNLRequestDidCompleteBlock)completion
{
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                             completion:completion];
    [self enqueueRequestOperation:op];
    return op;
}

- (void)syncAddRequestOperation:(TNLRequestOperation *)op
{
    tnl_dispatch_sync_autoreleasing(_sessionStateQueue, ^{
        if (self->_suspendCount > 0) {
            [self->_stagedRequestOperations addObject:op];
        } else {
            _GlobalRequestOperationQueueAddOperation(op);
        }
    });
}

- (void)clearQueuedRequestOperation:(TNLRequestOperation *)op
{
    tnl_dispatch_async_autoreleasing(_sessionStateQueue, ^{
        [self->_stagedRequestOperations removeObject:op];
    });
}

#pragma mark Cancel

static void _cancelAllStagedRequestOperations(SELF_ARG,
                                              id<TNLRequestOperationCancelSource> source,
                                              NSError * __nullable optionalUnderlyingError)
{
    if (!self) {
        return;
    }

    tnl_dispatch_async_autoreleasing(self->_sessionStateQueue, ^{
        NSArray<TNLRequestOperation *> *ops = [self->_stagedRequestOperations copy];
        [self->_stagedRequestOperations removeAllObjects];
        for (TNLRequestOperation *op in ops) {
            [op cancelWithSource:source
                 underlyingError:optionalUnderlyingError];
        }
    });
}

- (void)cancelAllWithSource:(id<TNLRequestOperationCancelSource>)source
            underlyingError:(nullable NSError *)optionalUnderlyingError
{
    _cancelAllStagedRequestOperations(self, source, optionalUnderlyingError);
    [[TNLURLSessionManager sharedInstance] cancelAllForQueue:self
                                                      source:source
                                             underlyingError:optionalUnderlyingError];
}

- (void)cancelAllWithSource:(id<TNLRequestOperationCancelSource>)source
{
    [self cancelAllWithSource:source
              underlyingError:nil];
}

#pragma mark Task Operation

- (void)findURLSessionTaskOperationForRequestOperation:(TNLRequestOperation *)op
                                              complete:(TNLRequestOperationQueueFindTaskOperationCompleteBlock)complete
{
    [[TNLURLSessionManager sharedInstance] findURLSessionTaskOperationForRequestOperationQueue:self
                                                                              requestOperation:op
                                                                                      complete:complete];
}

#pragma mark Request Events

- (void)operationDidStart:(TNLRequestOperation *)op
{
    _executeOnNetworkObservers(self,
                               @selector(tnl_requestOperationDidStart:),
                               ^(id<TNLNetworkObserver> observer) {
        [observer tnl_requestOperationDidStart:op];
    });
}

- (void)operation:(TNLRequestOperation *)op
        didStartAttemptWithMetrics:(TNLAttemptMetrics *)metrics
{
    NSURLRequest *URLRequest = op.currentURLRequest;

    _executeOnNetworkObservers(self,
                               @selector(tnl_requestOperation:didStartAttemptRequest:metrics:),
                               ^(id<TNLNetworkObserver> observer) {
        [observer tnl_requestOperation:op
                didStartAttemptRequest:URLRequest
                               metrics:metrics];
    });
}

- (void)operation:(TNLRequestOperation *)op
        didCompleteAttempt:(TNLResponse *)response
        disposition:(TNLAttemptCompleteDisposition)disposition
{
    _executeOnNetworkObservers(self,
                               @selector(tnl_requestOperation:didCompleteAttemptWithIntermediateResponse:disposition:),
                               ^(id<TNLNetworkObserver> observer) {
        [observer tnl_requestOperation:op
                  didCompleteAttemptWithIntermediateResponse:response
                  disposition:disposition];
    });
}

- (void)operation:(TNLRequestOperation *)op
        didCompleteWithResponse:(TNLResponse *)response
{
    _executeOnNetworkObservers(self,
                               @selector(tnl_requestOperation:didCompleteWithResponse:),
                               ^(id<TNLNetworkObserver> observer) {
        [observer tnl_requestOperation:op
               didCompleteWithResponse:response];
    });
}

- (void)taskOperation:(TNLURLSessionTaskOperation *)op
        didCompleteAttempt:(TNLResponse *)response
{
    TNLRequestOperation *requestOp = [op synthesizeRequestOperation];
    _executeOnNetworkObservers(self,
                               @selector(tnl_requestOperation:didCompleteWithResponse:),
                               ^(id<TNLNetworkObserver> observer) {
        [observer tnl_requestOperation:requestOp
               didCompleteWithResponse:response];
    });
}

#pragma mark Private

static void _executeOnNetworkObservers(SELF_ARG,
                                       SEL selector,
                                       void(^matchingBlock)(id<TNLNetworkObserver> matchingObserver))
{
    if (!self) {
        return;
    }

    tnl_dispatch_async_autoreleasing(_GlobalOperationQueueQueue(), ^{
        NSSet<id<TNLNetworkObserver>> *observers = [sGlobalNetworkObservers copy];
        tnl_dispatch_async_autoreleasing(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            for (id<TNLNetworkObserver> observer in observers) {
                if ([observer respondsToSelector:selector]) {
                    matchingBlock(observer);
                }
            }
        });
    });
    tnl_dispatch_async_autoreleasing(self->_sessionStateQueue, ^{
        if ([self->_networkObserver respondsToSelector:selector]) {
            matchingBlock(self->_networkObserver);
        }
    });
}

@end

#pragma mark - Functions

static void _GlobalRequestOperationQueueAddOperation(TNLRequestOperation *op)
{
    _GlobalApplyAutoDependenciesToOperation(op);
    _GlobalEnqueueOperation(op);
}

@implementation TNLNetwork

+ (BOOL)hasExecutingNetworkConnections
{
    return atomic_load(&sGlobalExecutingConnectionCount) > 0;
}

+ (void)incrementExecutingNetworkConnections
{
    if (atomic_fetch_add(&sGlobalExecutingConnectionCount, 1) == 0) {
        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:TNLNetworkExecutingNetworkConnectionsDidUpdateNotification
                                                                object:nil
                                                              userInfo:@{ TNLNetworkExecutingNetworkConnectionsExecutingKey : @YES }];
        });
    }
}

+ (void)decrementExecutingNetworkConnections
{
    const int64_t result = atomic_fetch_sub(&sGlobalExecutingConnectionCount, 1);
    if (1 == result) {
        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            // Post from main thread
            [[NSNotificationCenter defaultCenter] postNotificationName:TNLNetworkExecutingNetworkConnectionsDidUpdateNotification
                                                                object:nil
                                                              userInfo:@{ TNLNetworkExecutingNetworkConnectionsExecutingKey : @NO }];
        });
    } else if (result <= 0) {
        TNLLogWarning(@"%@ was called too many times!  Executing connections count is now negative!", NSStringFromSelector(_cmd));
    }
}

+ (void)serviceUnavailableEncounteredForURL:(NSURL *)URL
                            retryAfterDelay:(NSTimeInterval)delay
{
    [[TNLURLSessionManager sharedInstance] serviceUnavailableEncounteredForURL:URL
                                                               retryAfterDelay:delay];
}

+ (void)HTTPURLResponseEncounteredOutsideOfTNL:(NSHTTPURLResponse *)response
{
    if (response.statusCode == TNLHTTPStatusCodeServiceUnavailable) {
        NSURL *URL = response.URL;
        if (URL) {
            NSTimeInterval delay = TNLGlobalServiceUnavailableRetryAfterBackoffValueDefault;
            id retryAfterValue = response.tnl_parsedRetryAfterValue;
            if ([retryAfterValue isKindOfClass:[NSNumber class]]) {
                delay = [(NSNumber *)retryAfterValue doubleValue];
            } else if ([retryAfterValue isKindOfClass:[NSDate class]]) {
                delay = [(NSDate *)retryAfterValue timeIntervalSinceNow];
            }
            [self serviceUnavailableEncounteredForURL:URL retryAfterDelay:delay];
        }
    }
}

+ (void)applyServiceUnavailableBackoffDependenciesToOperation:(NSOperation *)op
                                                      withURL:(NSURL *)URL
                                            isLongPollRequest:(BOOL)isLongPoll
{
    [[TNLURLSessionManager sharedInstance] applyServiceUnavailableBackoffDependenciesToOperation:op
                                                                                         withURL:URL
                                                                               isLongPollRequest:isLongPoll];
}

@end

NS_ASSUME_NONNULL_END

//
//  TNLRequestOperation.m
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright © 2020 Twitter, Inc. All rights reserved.
//

#include <mach/mach_time.h>
#include <objc/message.h>
#include <stdatomic.h>

#import "NSCachedURLResponse+TNLAdditions.h"
#import "NSDictionary+TNLAdditions.h"
#import "NSURLRequest+TNLAdditions.h"
#import "NSURLResponse+TNLAdditions.h"
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "NSURLSessionTaskMetrics+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLAttemptMetaData_Project.h"
#import "TNLAttemptMetrics_Project.h"
#import "TNLContentCoding.h"
#import "TNLError.h"
#import "TNLGlobalConfiguration_Project.h"
#import "TNLHostSanitizer.h"
#import "TNLPriority.h"
#import "TNLRequest.h"
#import "TNLRequestDelegate.h"
#import "TNLRequestOperation_Project.h"
#import "TNLRequestOperationCancelSource.h"
#import "TNLRequestOperationQueue_Project.h"
#import "TNLRequestRetryPolicyProvider.h"
#import "TNLResponse_Project.h"
#import "TNLSimpleRequestDelegate.h"
#import "TNLTiming.h"
#import "TNLURLSessionTaskOperation.h"

NS_ASSUME_NONNULL_BEGIN

#define TAG_FROM_METHOD(DELEGATE, PROTOCOL, SEL) [NSString stringWithFormat:@"%@<%@>->%@", NSStringFromClass([DELEGATE class]), NSStringFromProtocol(PROTOCOL), NSStringFromSelector(SEL)]

static NSString * const kRedactedKeyValue = @"<redacted>";

static volatile atomic_uint_fast64_t sNextRetryId = ATOMIC_VAR_INIT(1);

static dispatch_queue_t _RequestOperationDefaultCallbackQueue(void);
static dispatch_queue_t _RequestOperationDefaultCallbackQueue()
{
    static dispatch_queue_t sFallbackQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sFallbackQueue = dispatch_queue_create("TNLRequestOperation.callback.queue", DISPATCH_QUEUE_SERIAL);
    });
    return sFallbackQueue;
}

static dispatch_queue_t _RetryPolicyProviderQueue(id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider);
static dispatch_queue_t _RetryPolicyProviderQueue(id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider)
{
    dispatch_queue_t q = NULL;
    if ([retryPolicyProvider respondsToSelector:@selector(tnl_callbackQueue)]) {
        q = [retryPolicyProvider tnl_callbackQueue];
    }
    if (!q) {
        q = _RequestOperationDefaultCallbackQueue();
    }
    return q;
}

static dispatch_queue_t _URLSessionTaskOperationPropertyQueue(void);
static dispatch_queue_t _URLSessionTaskOperationPropertyQueue()
{
    static dispatch_queue_t sQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sQueue = dispatch_queue_create("TNLRequestOperation.URLSessionTaskOperation.atomic.queue", DISPATCH_QUEUE_CONCURRENT);
    });
    return sQueue;
}

TNL_OBJC_FINAL TNL_OBJC_DIRECT_MEMBERS
@interface TNLTimerOperation : TNLSafeOperation
- (instancetype)initWithDelay:(NSTimeInterval)delay;
@end

@interface TNLRequestOperation ()

// Private Properties
#pragma twitter startignorestylecheck
@property (tnl_nonatomic_direct, readonly, nullable) id<TNLRequestDelegate> internalDelegate;
@property (tnl_atomic_direct, copy, nullable) NSString *cachedDelegateClassName; // annoyingly the Twitter style checker considers this a delegate, so we'll wrap it in the ignorestylecheck
#pragma twitter endignorestylecheck
@property (tnl_atomic_direct, nullable) NSError *terminalErrorOverride;
@property (tnl_atomic_direct, readonly) TNLResponseSource responseSource;
@property (tnl_nonatomic_direct, readonly) TNLRequestExecutionMode executionMode;
@property (tnl_atomic_direct) TNLPriority internalPriority;
@property (tnl_atomic_direct, nullable) TNLResponse *internalFinalResponse;

// Private Writability
@property (nonatomic, nullable) TNLRequestOperationQueue *requestOperationQueue;
@property (nonatomic, nullable) id<TNLRequest> hydratedRequest;
@property (nonatomic) float downloadProgress;
@property (nonatomic) float uploadProgress;
@property (atomic, nullable) TNLURLSessionTaskOperation *URLSessionTaskOperation;
@property (atomic, copy, nullable) NSDictionary<NSString *, id<TNLContentDecoder>> *additionalDecoders;
@property (atomic, copy, nullable) NSURLRequest *hydratedURLRequest;

@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLRequestOperation (Network)

// Methods that can only be called from the tnl_network_queue()

#pragma mark NSOperation helpers

- (void)_network_prepareToConnectThenConnect:(BOOL)isRetry;
- (void)_network_connect:(BOOL)isRetry;
- (void)_network_startURLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                                      isRetry:(BOOL)isRetry;
- (void)_network_fail:(NSError *)error;

#pragma mark NSOperation

- (void)_network_retryWithOldResponse:(TNLResponse *)oldResponse
                  retryPolicyProvider:(nullable id<TNLRequestRetryPolicyProvider>)retryPolicyProvider;
- (void)_network_prepareToStart;
- (void)_network_start:(BOOL)isRetry;
- (void)_network_cleanupAfterComplete;

#pragma mark Private Methods

- (void)_network_transitionToState:(TNLRequestOperationState)state
               withAttemptResponse:(nullable TNLResponse *)attemptResponse;
- (void)_network_completeTransitionFromState:(TNLRequestOperationState)oldState
                                     toState:(TNLRequestOperationState)state
                         withAttemptResponse:(nullable TNLResponse *)attemptResponse;
- (TNLResponse *)_network_finalizeResponseWithInfo:(TNLResponseInfo *)responseInfo
                                     responseError:(nullable NSError *)responseError
                                          metadata:(nullable TNLAttemptMetaData *)metadata
                                       taskMetrics:(nullable NSURLSessionTaskMetrics *)taskMetrics;
- (void)_network_applyEncodingMetricsToInfo:(TNLResponseInfo *)responseInfo
                               withMetaData:(nullable TNLAttemptMetaData *)metadata;
- (void)_network_updateMetricsFromState:(TNLRequestOperationState)oldState
                                toState:(TNLRequestOperationState)newState
                    withAttemptResponse:(nullable TNLResponse *)attemptResponse;
- (void)_network_didCompleteAttemptWithResponse:(TNLResponse *)response
                                    disposition:(TNLAttemptCompleteDisposition)disposition;
- (void)_network_completeWithResponse:(TNLResponse *)response;

#pragma mark Attempt Retry

// Primary "attempt retry" method
- (void)_network_attemptRetryDuringTransitionFromState:(TNLRequestOperationState)oldState
                                               toState:(TNLRequestOperationState)state
                                   withAttemptResponse:(nullable TNLResponse *)attemptResponse;

// Internal methods called by primary "attempt retry" method
- (BOOL)_network_shouldAttemptRetryDuringTransitionFromState:(TNLRequestOperationState)oldState
                                                     toState:(TNLRequestOperationState)state
                                         withAttemptResponse:(nullable TNLResponse *)attemptResponse;
- (BOOL)_network_shouldForciblyRetryInvalidatedURLSessionRequestWithAttemptResponse:(TNLResponse *)attemptResponse;
- (void)_network_forciblyRetryInvalidatedURLSessionRequestWithAttemptResponse:(TNLResponse *)attemptResponse;
- (void)_network_retryDuringTransitionFromState:(TNLRequestOperationState)oldState
                                        toState:(TNLRequestOperationState)state
                            withAttemptResponse:(TNLResponse *)attemptResponse
                            retryPolicyProvider:(id<TNLRequestRetryPolicyProvider>)retryPolicyProvider;

#pragma mark Retry

- (void)_network_startRetryWithDelay:(NSTimeInterval)retryDelay
                         oldResponse:(TNLResponse *)oldResponse
                 retryPolicyProvider:(nullable id<TNLRequestRetryPolicyProvider>)retryPolicyProvider;
- (void)_network_invalidateRetry;
- (void)_network_tryRetryWithId:(uint64_t)retryId
                    oldResponse:(TNLResponse *)oldResponse
            retryPolicyProvider:(nullable id<TNLRequestRetryPolicyProvider>)retryPolicyProvider;

#pragma mark Operation Timeout Timer

- (void)_network_startOperationTimeoutTimer:(NSTimeInterval)timeInterval;
- (void)_network_invalidateOperationTimeoutTimer;
- (void)_network_operationTimeoutTimerDidFire;

#pragma mark Callback Timeout Timer

- (void)_network_startCallbackTimerWithAlreadyElapsedDuration:(NSTimeInterval)alreadyElapsedTime;
- (void)_network_startCallbackTimerIfNecessary;
- (void)_network_stopCallbackTimer;
- (void)_network_callbackTimerFired;
#if TARGET_OS_IOS || TARGET_OS_TV
- (void)_network_pauseCallbackTimer;
- (void)_network_unpauseCallbackTimer;
#endif

#pragma mark Attempt Timeout Timer

- (void)_network_startAttemptTimeoutTimer:(NSTimeInterval)timeInterval;
- (void)_network_invalidateAttemptTimeoutTimer;
- (void)_network_attemptTimeoutTimerDidFire;

#pragma mark Application States (iOS only)

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)_network_startObservingApplicationStates;
- (void)_dealloc_stopObservingApplicationStatesIfNecessary;
#endif
- (void)_network_willResignActive;
- (void)_network_didBecomeActive;

#pragma mark Background (iOS only)

- (void)_network_startBackgroundTask;
- (void)_network_endBackgroundTask;

#pragma mark State

- (BOOL)_network_isStateActive;
- (BOOL)_network_isStateFinished;
- (BOOL)_network_isStateCancelled;
- (BOOL)_network_hasFailed;
- (BOOL)_network_hasFailedOrFinished;
- (BOOL)_network_isPreparing;

#pragma mark Preparation Methods

/*
 Use static C functions instead of ObjC methods for simpler iteration while avoiding __TEXT binary overhead
 */

typedef void (^tnl_request_preparation_block_t)(void);

static void _network_prepStep_validateOriginalRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_hydrateRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_validateHydratedRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_convertHydratedRequestToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_validateConfiguration(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_applyGlobalHeadersToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_applyAcceptEncodingsToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_applyContentEncodingToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_sanitizeHostForScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_authorizeScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);
static void _network_prepStep_cementScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock);

- (void)_network_prepareRequestStep:(size_t)preparationStepIndex
                            isRetry:(BOOL)isRetry;

@end

typedef void (*tnl_request_preparation_function_ptr)(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t block);
static const tnl_request_preparation_function_ptr _Nonnull sPreparationFunctions[] = {
    _network_prepStep_validateOriginalRequest,
    _network_prepStep_hydrateRequest,
    _network_prepStep_validateHydratedRequest,
    _network_prepStep_convertHydratedRequestToScratchURLRequest,
    _network_prepStep_validateConfiguration,
    _network_prepStep_applyGlobalHeadersToScratchURLRequest,
    _network_prepStep_applyAcceptEncodingsToScratchURLRequest,
    _network_prepStep_applyContentEncodingToScratchURLRequest,
    _network_prepStep_sanitizeHostForScratchURLRequest,
    _network_prepStep_authorizeScratchURLRequest,
    _network_prepStep_cementScratchURLRequest,
};
static const size_t kPreparationFunctionsCount = (sizeof(sPreparationFunctions) / sizeof(sPreparationFunctions[0]));

TNL_OBJC_DIRECT_MEMBERS
@interface TNLRequestOperation (Tagging)

- (void)_updateTag:(NSString *)tag;
- (void)_clearTag:(NSString *)tag;

@end

#pragma mark - TNLRequestOperation

TNLStaticAssert(sizeof(TNLRequestOperationState_Unaligned_AtomicT) == sizeof(TNLRequestOperationState), enum_size_missmatch);

@implementation TNLRequestOperation
{
    dispatch_queue_t _callbackQueue; // could be concurrent, call with barrier
    dispatch_queue_t _completionQueue; // could be concurrent, call with barrier
    TNLPriority _enqueuedPriority;
    NSMutableArray *_callbackTagStack;
    uint64_t _mach_callbackTagTime;
    NSError *_cachedCancelError;
    id<TNLRequestDelegate> _strongDelegate;
    TNLBackgroundTaskIdentifier _backgroundTaskIdentifier;
    NSTimeInterval _cloggedCallbackTimeout;
    TNLRequestOperationState_AtomicT _state;
    NSMutableURLRequest *_scratchURLRequest;
    NSTimeInterval _scratchURLRequestEncodeLatency;
    SInt64 _scratchURLRequestOriginalBodyLength;
    SInt64 _scratchURLRequestEncodedBodyLength;
    id<TNLHostSanitizer> _hostSanitizer;
    TNLResponseMetrics *_metrics;

    // Timers
    dispatch_source_t _operationTimeoutTimerSource;
    dispatch_source_t _attemptTimeoutTimerSource;
    dispatch_source_t _callbackTimeoutTimerSource;
    uint64_t _callbackTimeoutTimerStartMachTime;
    uint64_t _callbackTimeoutTimerPausedMachTime;

    // Retry
    uint64_t _activeRetryId;

    // Flags that can only be written on the background queue
    struct {
        BOOL didEnqueue:1;
        BOOL didStart:1;
        BOOL didPrep:1;
        BOOL inRetryCheck:1;
        BOOL silentStart:1;
        BOOL isCallbackClogDetectionEnabled:1;
        BOOL isObservingApplicationStates:1;
        BOOL applicationIsInBackground:1;
        unsigned int invalidSessionRetryCount:4;
    } _backgroundFlags;

    // atomic properties support
    TNLURLSessionTaskOperation *_URLSessionTaskOperation;
    volatile atomic_bool _didCompleteFinishedCallback;
}

#pragma mark overrides with no behavior change

- (void)addDependency:(NSOperation *)op
{
    [super addDependency:op];
}

- (void)waitUntilFinished
{
    [super waitUntilFinished];
}

#pragma mark init/dealloc

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (instancetype)init
#pragma clang diagnostic pop
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initWithRequest:(nullable id<TNLRequest>)request responseClass:(nullable Class)responseClass configuration:(nullable TNLRequestConfiguration *)config delegate:(nullable id<TNLRequestDelegate>)delegate
{
    if (self = [super init]) {
        TNLIncrementObjectCount([self class]);

        arc4random_buf(&_operationId, sizeof(int64_t));

        _backgroundTaskIdentifier = TNLBackgroundTaskInvalid;

        atomic_init(&_state, TNLRequestOperationStateIdle);
        atomic_init(&_didCompleteFinishedCallback, false);
        _originalRequest = [request conformsToProtocol:@protocol(NSCopying)] ? [(NSObject *)request copy] : request;

        if (!config) {
            config = [TNLRequestConfiguration defaultConfiguration];
        }
        _requestConfiguration = [config copy];
        _requestDelegate = delegate;
        if ([delegate isKindOfClass:[TNLSimpleRequestDelegate class]]) {
            _strongDelegate = delegate;
        } else if (delegate) {
            _cachedDelegateClassName = NSStringFromClass([delegate class]);
        }
        _metrics = [[TNLResponseMetrics alloc] init];

        _callbackTagStack = [[NSMutableArray alloc] init];
        _cloggedCallbackTimeout = [TNLGlobalConfiguration sharedInstance].requestOperationCallbackTimeout;
        _backgroundFlags.isCallbackClogDetectionEnabled = _cloggedCallbackTimeout > 0.0 && _requestConfiguration.executionMode != TNLRequestExecutionModeBackground;

        _responseClass = [TNLResponse class];
        if (responseClass) {
            if ([responseClass isSubclassOfClass:_responseClass]) {
                _responseClass = responseClass;
            } else {
                TNLLogError(@"%1$@ is not a subclass of %2$@!  Using %2$@ instead", NSStringFromClass(responseClass), NSStringFromClass(_responseClass));
                TNLAssert([responseClass isSubclassOfClass:_responseClass]);
            }
        }
    }
    return self;
}

- (TNLBackgroundTaskIdentifier)dealloc_backgroundTaskIdentifier TNL_THREAD_SANITIZER_DISABLED
{
    return _backgroundTaskIdentifier;
}

- (BOOL)dealloc_isObservingApplicationStates TNL_THREAD_SANITIZER_DISABLED
{
    return _backgroundFlags.isObservingApplicationStates;
}

- (void)dealloc
{
    tnl_dispatch_timer_invalidate(_operationTimeoutTimerSource);
    tnl_dispatch_timer_invalidate(_attemptTimeoutTimerSource);
    tnl_dispatch_timer_invalidate(_callbackTimeoutTimerSource);
    _activeRetryId = 0; // invalidate any pending retry

    TNLBackgroundTaskIdentifier backgroundTaskIdentifier = self.dealloc_backgroundTaskIdentifier;
    if (TNLBackgroundTaskInvalid != backgroundTaskIdentifier) {
        [[TNLGlobalConfiguration sharedInstance] endBackgroundTaskWithIdentifier:backgroundTaskIdentifier];
    }

#if TARGET_OS_IOS || TARGET_OS_TV
    [self _dealloc_stopObservingApplicationStatesIfNecessary];
#endif

    TNLDecrementObjectCount([self class]);
}

#pragma mark Constructors

+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       responseClass:(nullable Class)responseClass
                       configuration:(nullable TNLRequestConfiguration *)config
                            delegate:(nullable id<TNLRequestDelegate>)delegate
{
    return [[self alloc] initWithRequest:request responseClass:responseClass configuration:config delegate:delegate];
}

#pragma mark Prep Methods

- (void)enqueueToOperationQueue:(TNLRequestOperationQueue *)operationQueue
{
    TNLAssert(!_requestOperationQueue);
    self.requestOperationQueue = operationQueue;
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        TNLAssert(!self->_backgroundFlags.didEnqueue);
        if (!self->_backgroundFlags.didEnqueue && atomic_load(&self->_state) == TNLRequestOperationStateIdle) {
            self->_enqueuedPriority = self.internalPriority;
            [self->_metrics didEnqueue];
            self->_backgroundFlags.didEnqueue = YES;
            [self->_requestOperationQueue syncAddRequestOperation:self];
        }
    });
}

#pragma mark Properties

- (nullable TNLURLSessionTaskOperation *)URLSessionTaskOperation
{
    __block TNLURLSessionTaskOperation *op;
    dispatch_sync(_URLSessionTaskOperationPropertyQueue(), ^{
        op = self->_URLSessionTaskOperation;
    });
    return op;
}

- (void)setURLSessionTaskOperation:(nullable TNLURLSessionTaskOperation *)URLSessionTaskOperation
{
    __block TNLURLSessionTaskOperation *oldOp = nil;
    dispatch_barrier_sync(_URLSessionTaskOperationPropertyQueue(), ^{
        oldOp = self->_URLSessionTaskOperation;
        self->_URLSessionTaskOperation = URLSessionTaskOperation;
    });

    if (oldOp) {
        [oldOp dissassociateRequestOperation:self];
    }
}

#pragma mark Private Properties

- (nullable id<TNLRequestDelegate>)internalDelegate
{
    id<TNLRequestDelegate> delegate = _strongDelegate ?: _requestDelegate;
    NSString *delegateClassName = self.cachedDelegateClassName;
    if (!delegate && delegateClassName) {
        TNLLogWarning(@"The TNLRequestDelegate (%@) of this TNLRequestOperation (%p) is nil.  It is possible the delegate was only held weakly and was deallocated unexpectedly.  Either cancel the TNLRequestOperation from the delegate's dealloc or maintain a strong reference to the delegate when used with a TNLRequestOperation (like setting the delegate as the operation's context property).", delegateClassName, self);
    }
    return delegate;
}

- (TNLRequestExecutionMode)executionMode
{
    return _requestConfiguration.executionMode;
}

- (TNLRequestOperationState)state
{
    return atomic_load(&_state);
}

- (void)setState:(TNLRequestOperationState)state async:(BOOL)async
{
    if (async) {
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            [self _tnl_setState:state];
        });
    } else {
        [self _tnl_setState:state];
    }
}

- (void)_tnl_setState:(TNLRequestOperationState)state
{
    [self willChangeValueForKey:@"state"];
    atomic_store(&_state, state);
    if (TNLRequestOperationStateStarting == state && _backgroundFlags.silentStart) {
        // clear the silent start flag
        _backgroundFlags.silentStart = 0;
    }
    [self didChangeValueForKey:@"state"];
}

- (void)setHydratedRequest:(nullable id<TNLRequest>)hydratedRequest
{
    if (_hydratedRequest != hydratedRequest) {
        _hydratedRequest = [hydratedRequest conformsToProtocol:@protocol(NSCopying)] ? [(NSObject *)hydratedRequest copy] : hydratedRequest;
    }
}

#pragma mark Hybrid override and redirect properties

- (nullable NSError *)error
{
    return self.terminalErrorOverride ?: self.response.operationError ?: self.URLSessionTaskOperation.error;
}

#pragma mark Redirected Properties

- (nullable TNLResponse *)response
{
    return self.internalFinalResponse;
}

- (NSUInteger)attemptCount
{
    return _metrics.attemptCount;
}

- (NSUInteger)retryCount
{
    return _metrics.retryCount;
}

- (NSUInteger)redirectCount
{
    return _metrics.redirectCount;
}

- (nullable NSURLRequest *)currentURLRequest
{
    return self.URLSessionTaskOperation.currentURLRequest ?: self.URLSessionTaskOperation.originalURLRequest;
}

- (nullable NSHTTPURLResponse *)currentURLResponse
{
    return self.URLSessionTaskOperation.URLResponse;
}

- (TNLResponseSource)responseSource
{
    return self.URLSessionTaskOperation.responseSource;
}

#pragma mark NSOperation Overrides

- (NSOperationQueuePriority)queuePriority
{
    return TNLConvertTNLPriorityToQueuePriority(_backgroundFlags.didEnqueue ? _enqueuedPriority : self.internalPriority);
}

- (NSQualityOfService)qualityOfService
{
    return TNLConvertTNLPriorityToQualityOfService(_backgroundFlags.didEnqueue ? _enqueuedPriority : self.internalPriority);
}

#pragma mark Priority

- (void)setPriority:(TNLPriority)priority
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (self.internalPriority != priority) {

            BOOL didEnqueue = self->_backgroundFlags.didEnqueue; // cannot modify other NSOperation priorities if we've already been enqueued
            BOOL qos = NO;
            if (!didEnqueue) {
                qos = [self respondsToSelector:@selector(setQualityOfService:)];
                [self willChangeValueForKey:@"queuePriority"];
                if (qos) {
                    [self willChangeValueForKey:@"qualityOfService"];
                }
            }

            self.internalPriority = priority;

            if (!didEnqueue) {
                if (qos) {
                    [self didChangeValueForKey:@"qualityOfService"];
                }
                [self didChangeValueForKey:@"queuePriority"];
            }

            [self.URLSessionTaskOperation network_priorityDidChangeForRequestOperation:self];
        }
    });
}

- (TNLPriority)priority
{
    return self.internalPriority;
}

#pragma mark Project Methods

- (void)network_URLSessionTaskOperationIsWaitingForConnectivity:(TNLURLSessionTaskOperation *)taskOp
{
    TNLAssertIsNetworkQueue();
    if (![self _network_hasFailedOrFinished] && self.URLSessionTaskOperation == taskOp) {

        // Invalidate timeout timer if configured to do so
        if (TNL_BITMASK_INTERSECTS_FLAGS(_requestConfiguration.connectivityOptions, TNLRequestConnectivityOptionInvalidateAttemptTimeoutWhenWaitForConnectivityTriggered)) {
            [self _network_invalidateAttemptTimeoutTimer];
        }

        // Send event
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperationIsWaitingForConnectivity:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperationIsWaitingForConnectivity:self];
                [self _clearTag:tag];
            });
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                  didReceiveURLResponse:(NSURLResponse *)URLResponse
{
    TNLAssertIsNetworkQueue();
    if (![self _network_hasFailedOrFinished] && self.URLSessionTaskOperation == taskOp) {
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didReceiveURLResponse:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperation:self
                             didReceiveURLResponse:URLResponse];
                [self _clearTag:tag];
            });
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
         willPerformRedirectFromRequest:(NSURLRequest *)fromRequest
                       withHTTPResponse:(NSHTTPURLResponse *)response
                              toRequest:(NSURLRequest *)toRequest
                             completion:(TNLRequestRedirectCompletionBlock)completion
{
    TNLAssertIsNetworkQueue();
    // provide the redirect policy
    [self _network_willPerformRedirectFromRequest:fromRequest
                                 withHTTPResponse:response
                                        toRequest:toRequest
                                 forTaskOperation:taskOp
                                   redirectPolicy:_requestConfiguration.redirectPolicy
                                       completion:completion];
}

- (void)_network_willPerformRedirectFromRequest:(NSURLRequest *)fromRequest
                               withHTTPResponse:(NSHTTPURLResponse *)response
                                      toRequest:(NSURLRequest *)providedToRequest
                               forTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                                 redirectPolicy:(TNLRequestRedirectPolicy)redirectPolicy
                                     completion:(TNLRequestRedirectCompletionBlock)completion TNL_OBJC_DIRECT
{
    TNLAssertIsNetworkQueue();
    if (![self _network_hasFailedOrFinished] && self.URLSessionTaskOperation == taskOp) {
        NSURLRequest *toRequest = providedToRequest;
        switch (redirectPolicy) {
            case TNLRequestRedirectPolicyDontRedirect:
                toRequest = nil;
                break;
            case TNLRequestRedirectPolicyDoRedirect:
                // permit redirect
                break;
            case TNLRequestRedirectPolicyRedirectToSameHost:
                if (![fromRequest.URL.host.lowercaseString isEqualToString:toRequest.URL.host.lowercaseString]) {
                    toRequest = nil;
                }
                break;
            case TNLRequestRedirectPolicyUseCallback:
            {
                id<TNLRequestRedirecter> redirecter = self.internalDelegate;
                SEL callback = @selector(tnl_requestOperation:willRedirectFromRequest:withResponse:toRequest:completion:);
                if ([redirecter respondsToSelector:callback]) {
                    tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                        NSString *tag = TAG_FROM_METHOD(redirecter, @protocol(TNLRequestRedirecter), callback);
                        [self _updateTag:tag];
                        [redirecter tnl_requestOperation:self
                                 willRedirectFromRequest:fromRequest
                                            withResponse:response
                                               toRequest:toRequest
                                              completion:^(id<TNLRequest> finalToRequest) {
                            [self _clearTag:tag];
                            // all `TNLURLSessionTaskOperationDelegate` completion blocks must be called from tnl_network_queue
                            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                                completion(finalToRequest);
                            });
                        }];
                    });
                } else {
                    // No callback to call, revert to Default behavior
                    TNLLogWarning(@"Use callback specified in redirect policy but %@ not implemented in delegate (%@)", NSStringFromProtocol(@protocol(TNLRequestRedirecter)), redirecter);
                    [self _network_willPerformRedirectFromRequest:fromRequest
                                                 withHTTPResponse:response
                                                        toRequest:toRequest
                                                 forTaskOperation:taskOp
                                                   redirectPolicy:TNLRequestRedirectPolicyDefault
                                                       completion:completion];
                }
                return;
            }
        }

        completion(toRequest);
    } else {
        completion(nil);
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                         redirectedFrom:(NSURLRequest *)fromRequest
                       withHTTPResponse:(NSHTTPURLResponse *)response
                                     to:(NSURLRequest *)toRequest
                               metaData:(TNLAttemptMetaData *)metaData
{
    TNLAssertIsNetworkQueue();
    if (![self _network_hasFailedOrFinished] && self.URLSessionTaskOperation == taskOp) {

        // Capture info from attempt

        NSDate *dateNow = [NSDate date];
        const uint64_t machTime = mach_absolute_time();
        [_metrics addMetaData:metaData taskMetrics:nil];
        [_metrics addEndDate:dateNow
                    machTime:machTime
                    response:response
              operationError:nil];
        [_metrics addRedirectStartWithDate:dateNow
                                  machTime:machTime
                                   request:toRequest];

        TNLResponseMetrics *metrics = [_metrics deepCopyAndTrimIncompleteAttemptMetrics:YES];
        TNLResponseInfo *info = [[TNLResponseInfo alloc] initWithFinalURLRequest:fromRequest
                                                                     URLResponse:response
                                                                          source:((response.tnl_wasCachedResponse) ? TNLResponseSourceLocalCache : TNLResponseSourceNetworkRequest)
                                                                            data:nil
                                                              temporarySavedFile:nil];
        TNLResponse *placeholderResponse = [self.responseClass responseWithRequest:self.originalRequest
                                                                    operationError:nil
                                                                              info:info
                                                                           metrics:metrics];

        // Complete attempt
        [self _network_didCompleteAttemptWithResponse:placeholderResponse
                                          disposition:TNLAttemptCompleteDispositionRedirecting];
        [self.requestOperationQueue operation:self
                   didStartAttemptWithMetrics:_metrics.attemptMetrics.lastObject];

        // Event the redirect
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didRedirectFromURLRequest:toURLRequest:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperation:self
                         didRedirectFromURLRequest:fromRequest
                                      toURLRequest:toRequest];
                [self _clearTag:tag];
            });
        }
   }
}

- (void)_network_notifySanitizedHost:(NSString *)oldHost
                              toHost:(NSString *)newHost TNL_OBJC_DIRECT
{
    TNLAssertIsNetworkQueue();
    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:didSanitizeFromHost:toHost:);
    if ([eventHandler respondsToSelector:callback]) {
        tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
            NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
            [self _updateTag:tag];
            [eventHandler tnl_requestOperation:self
                           didSanitizeFromHost:oldHost
                                        toHost:newHost];
            [self _clearTag:tag];
        });
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                    redirectFromRequest:(NSURLRequest *)fromRequest
                       withHTTPResponse:(NSHTTPURLResponse *)response
                                     to:(NSURLRequest *)toRequest
                      completionHandler:(void (^)(NSURLRequest * __nullable, NSError * __nullable))completionHandler
{
    TNLAssertIsNetworkQueue();
    if (_hostSanitizer) {
        NSString *host = toRequest.URL.host;
        [_hostSanitizer tnl_host:host
     wasEncounteredForURLRequest:toRequest
                      asRedirect:YES
                      completion:^(TNLHostSanitizerBehavior behavior, NSString *newHost) {
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                TNLAssert([host isEqualToString:toRequest.URL.host]);
                NSError *error = nil;
                NSMutableURLRequest *mRequest = [toRequest mutableCopy];
                const TNLHostReplacementResult hostReplacementResult = [mRequest tnl_replaceURLHost:newHost
                                                                                           behavior:behavior
                                                                                              error:&error];
                if (TNLHostReplacementResultSuccess == hostReplacementResult) {
                    [self _network_notifySanitizedHost:host toHost:newHost];
                } else {
                    mRequest = nil;
                }

                if (error) {
                    [self _network_fail:error];
                }

                completionHandler(mRequest ?: toRequest, error);
            });
        }];
    } else {
        completionHandler(toRequest, nil);
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                didUpdateUploadProgress:(float)progress
{
    TNLAssertIsNetworkQueue();
    // Progress can exceed 1.0, cap it
    if (progress > 1.0f) {
        progress = 1.0f;
    }

    if (self.URLSessionTaskOperation != taskOp || _uploadProgress == progress) {
        return;
    }

    self.uploadProgress = progress;
    if (![self _network_hasFailedOrFinished]) {
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didUpdateUploadProgress:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperation:self
                           didUpdateUploadProgress:progress];
                [self _clearTag:tag];
            });
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
              didUpdateDownloadProgress:(float)progress
{
    TNLAssertIsNetworkQueue();
    // Progress can exceed 1.0, cap it
    if (progress > 1.0f) {
        progress = 1.0f;
    }

    if (self.URLSessionTaskOperation != taskOp || self->_downloadProgress == progress) {
        return;
    }

    self.downloadProgress = progress;
    if (![self _network_hasFailedOrFinished]) {
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didUpdateDownloadProgress:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperation:self
                         didUpdateDownloadProgress:progress];
                [self _clearTag:tag];
            });
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                     appendReceivedData:(NSData *)data
{
    TNLAssertIsNetworkQueue();
    if (![self _network_hasFailedOrFinished] && self.URLSessionTaskOperation == taskOp) {
        switch (_requestConfiguration.responseDataConsumptionMode) {
            case TNLResponseDataConsumptionModeChunkToDelegateCallback: {
                id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
                SEL callback = @selector(tnl_requestOperation:didReceiveData:);
                if ([eventHandler respondsToSelector:callback]) {
                    tnl_dispatch_barrier_async_autoreleasing(self->_callbackQueue, ^{
                        NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                        [self _updateTag:tag];
                        [eventHandler tnl_requestOperation:self
                                            didReceiveData:data];
                        [self _clearTag:tag];
                    });
                }
                break;
            }
            case TNLResponseDataConsumptionModeNone:
            case TNLResponseDataConsumptionModeStoreInMemory:
            case TNLResponseDataConsumptionModeSaveToDisk:
                TNLAssertNever();
                break;
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
        didStartTaskWithTaskIdentifier:(NSUInteger)taskId
        configIdentifier:(nullable NSString *)configIdentifier
        sharedContainerIdentifier:(nullable NSString *)sharedContainerIdentifier
        isBackgroundRequest:(BOOL)isBackgroundRequest
{
    TNLAssertIsNetworkQueue();
    if (![self _network_hasFailedOrFinished] && self.URLSessionTaskOperation == taskOp) {
        TNLAssert((self.executionMode == TNLRequestExecutionModeBackground) == isBackgroundRequest);
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didStartRequestWithURLSessionTaskIdentifier:URLSessionConfigurationIdentifier:URLSessionSharedContainerIdentifier:isBackgroundRequest:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperation:self
                              didStartRequestWithURLSessionTaskIdentifier:taskId
                              URLSessionConfigurationIdentifier:configIdentifier
                              URLSessionSharedContainerIdentifier:sharedContainerIdentifier
                              isBackgroundRequest:isBackgroundRequest];
                [self _clearTag:tag];
            });
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
               finalizeWithResponseInfo:(TNLResponseInfo *)responseInfo
                          responseError:(nullable NSError *)responseError
                               metaData:(TNLAttemptMetaData *)metadata
                            taskMetrics:(nullable NSURLSessionTaskMetrics *)taskMetrics
                             completion:(TNLRequestMakeFinalResponseCompletionBlock)completion
{
    TNLAssertIsNetworkQueue();
    if (self.URLSessionTaskOperation != taskOp || [self _network_hasFailedOrFinished]) {
        completion(nil);
        return;
    }

    TNLResponse *response = [self _network_finalizeResponseWithInfo:responseInfo
                                                      responseError:responseError
                                                           metadata:metadata
                                                        taskMetrics:taskMetrics];
    completion(response);
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                   didTransitionToState:(TNLRequestOperationState)state
                           withResponse:(nullable TNLResponse *)response
{
    TNLAssertIsNetworkQueue();
    TNLAssert(state != TNLRequestOperationStateIdle);
    if (self.URLSessionTaskOperation != taskOp || [self _network_hasFailedOrFinished]) {
        return;
    }

    [self _network_transitionToState:state withAttemptResponse:response];
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
         didStartSessionTaskWithRequest:(NSURLRequest *)request
{
    TNLAssertIsNetworkQueue();
    if (self.URLSessionTaskOperation != taskOp || [self _network_hasFailedOrFinished]) {
        return;
    }

    TNLRequestOperationState state = atomic_load(&_state);
    if (TNLRequestOperationStateStarting == state) {
        [_metrics updateCurrentRequest:request];
    }
}

#pragma mark Wait

- (void)waitUntilFinishedWithoutBlockingRunLoop
{
    // Default implementation is to block the thread until the execution completes.
    // This can deadlock if the caller is not careful and the completion queue or callback queue
    // are the same thread that waitUntilFinished are called from.
    // In this method, we'll pump the run loop until we're finished as a way to provide an alternative.

    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    if (!runLoop) {
        return [self waitUntilFinished];
    }

    while (!self.isFinished) {
        [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    }
}

#pragma mark Cancel

- (void)cancel
{
    [self cancelWithSource:[[TNLOperationCancelMethodCancelSource alloc] init]
           underlyingError:nil];
}

- (void)cancelWithSource:(id<TNLRequestOperationCancelSource>)source
{
    [self cancelWithSource:source
           underlyingError:nil];
}

- (void)cancelWithSource:(id<TNLRequestOperationCancelSource>)source
         underlyingError:(nullable NSError *)optionalUnderlyingError
{
    NSParameterAssert(source != nil);

    // A cancel can easily be followed by a weak delegate being deallocated.
    // Clear our cached delegate class name so that we don't warn about the delegate being nil.
    self.cachedDelegateClassName = nil;

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (self->_cachedCancelError || [self _network_hasFailedOrFinished]) {
            return;
        }

        NSError *error = TNLErrorFromCancelSource(source, optionalUnderlyingError);
        self->_cachedCancelError = error;
        [self _network_fail:error];
    });
}

#pragma mark NSOperation

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (BOOL)isFinished
{
    return [self _network_isStateFinished] && atomic_load(&_didCompleteFinishedCallback);
}

- (BOOL)isCancelled
{
    return [self _network_isStateCancelled];
}

- (BOOL)isExecuting
{
    if ([self _network_isStateActive]) {
        return YES;
    }
    if (TNLRequestOperationStateIsFinal(atomic_load(&_state))) {
        return !atomic_load(&_didCompleteFinishedCallback);
    }
    return NO;
}

- (void)start
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        TNLAssert(!self->_backgroundFlags.didStart);
        TNLAssert(self->_backgroundFlags.didEnqueue);
        TNLAssert(self->_requestOperationQueue);
        TNLAssert(self->_requestConfiguration);

        if ([self _network_hasFailedOrFinished]) {
            // might have been pre-emptively cancelled or failed
            return;
        }

        [self _network_prepareToStart];

        self->_backgroundFlags.didStart = YES;
        [self->_requestOperationQueue operationDidStart:self];
        [self _network_startOperationTimeoutTimer:self->_requestConfiguration.operationTimeout];
        TNLAssert(self->_metrics.attemptCount == 0);

        if (self->_cachedCancelError) {
            [self _network_fail:self->_cachedCancelError];
        } else {
            [self _network_start:NO /*isRetry*/];
        }
    });
}

@end

#pragma mark - TNLRequestOperation (Network)

@implementation TNLRequestOperation (Network)

#pragma mark Operation State Accessors

- (BOOL)_network_isStateFinished
{
    return TNLRequestOperationStateIsFinal(atomic_load(&_state));
}

- (BOOL)_network_isStateCancelled
{
    return TNLRequestOperationStateCancelled == atomic_load(&_state);
}

- (BOOL)_network_isStateActive
{
    return TNLRequestOperationStateIsActive(atomic_load(&_state));
}

- (BOOL)_network_hasFailed
{
    return self.terminalErrorOverride != nil;
}

- (BOOL)_network_hasFailedOrFinished
{
    return [self _network_hasFailed] || [self _network_isStateFinished];
}

- (BOOL)_network_isPreparing
{
    return self.state == TNLRequestOperationStatePreparingRequest && ![self _network_hasFailedOrFinished];
}

#pragma mark Preparation Methods

- (void)_network_prepareRequestStep:(size_t)preparationStepIndex
                            isRetry:(BOOL)isRetry
{
    if (![self _network_isPreparing]) {
        return;
    }

    if (preparationStepIndex >= kPreparationFunctionsCount) {
        [self _network_connect:isRetry];
        return;
    }

    tnl_request_preparation_function_ptr prepareStep = sPreparationFunctions[preparationStepIndex];
    prepareStep(self, ^{
        [self _network_prepareRequestStep:preparationStepIndex+1 isRetry:isRetry];
    });
}

static void _network_prepStep_validateOriginalRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    id<TNLRequest> originalRequest = self.originalRequest;
    NSError *error = nil;
    if (!originalRequest) {
        error = TNLErrorCreateWithCode(TNLErrorCodeRequestOperationRequestNotProvided);
    }

    if (error) {
        [self _network_fail:error];
    } else {
        nextBlock();
    }
}

static void _network_prepStep_hydrateRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    id<TNLRequestHydrater> hydrater = self.internalDelegate;
    id<TNLRequest> originalRequest = self.originalRequest;
    SEL callback = @selector(tnl_requestOperation:hydrateRequest:completion:);
    tnl_dispatch_barrier_async_autoreleasing(self->_callbackQueue, ^{
        if ([hydrater respondsToSelector:callback]) {
            NSString *tag = TAG_FROM_METHOD(hydrater, @protocol(TNLRequestHydrater), callback);
            [self _updateTag:tag];
            [hydrater tnl_requestOperation:self
                            hydrateRequest:originalRequest
                                completion:^(id<TNLRequest> hydratedRequest, NSError *error) {
                [self _clearTag:tag];

                tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                    if (![self _network_isPreparing]) {
                        return;
                    }

                    if (error) {
                        [self _network_fail:TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationFailedToHydrateRequest, error)];
                    } else {
                        self.hydratedRequest = hydratedRequest ?: originalRequest;
                        nextBlock();
                    }
                });
            }];
        } else {
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                self.hydratedRequest = originalRequest;
                nextBlock();
            });
        }
    });
}

static void _network_prepStep_validateHydratedRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    id<TNLRequest> hydratedRequest = self.hydratedRequest;
    NSError *underlyingError;

    // Validate the request itself
    const BOOL isValid = TNLRequestValidate(hydratedRequest,
                                            self->_requestConfiguration,
                                            &underlyingError);
    if (!isValid) {
        [self _network_fail:TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationInvalidHydratedRequest, underlyingError)];
        return;
    }

    nextBlock();
}

static void _network_prepStep_convertHydratedRequestToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    NSError *error = nil;
    id<TNLRequest> request = self.hydratedRequest;
    NSMutableURLRequest *mURLRequest = TNLRequestToNSMutableURLRequest(request,
                                                                       self.requestConfiguration,
                                                                       &error);
    if (!mURLRequest) {
        [self _network_fail:error];
        return;
    }

    self->_scratchURLRequest = mURLRequest;
    self->_scratchURLRequestEncodeLatency = 0;
    self->_scratchURLRequestOriginalBodyLength = 0;
    self->_scratchURLRequestEncodedBodyLength = 0;
    nextBlock();
}

static void _network_prepStep_validateConfiguration(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    TNLRequestConfiguration *config = self->_requestConfiguration;

    const BOOL hasAttemptTimeout = config.attemptTimeout >= MIN_TIMER_INTERVAL;
    const BOOL hasIdleTimeout = config.idleTimeout >= MIN_TIMER_INTERVAL;
    const BOOL hasOperationTimeout = config.operationTimeout >= MIN_TIMER_INTERVAL;

    if (hasAttemptTimeout && hasIdleTimeout && (config.attemptTimeout - config.idleTimeout < -0.05)) {
        TNLLogWarning(@"Attempt Timeout (%.2f) should not be shorter than the Idle Timeout (%.2f)!", config.attemptTimeout, config.idleTimeout);
    }

    if (hasOperationTimeout && hasAttemptTimeout && (config.operationTimeout - config.attemptTimeout < -0.05)) {
        TNLLogWarning(@"Operation Timeout (%.2f) should not be shorter than the Attempt Timeout (%.2f)!", config.operationTimeout, config.attemptTimeout);
    }

    if (config.executionMode == TNLRequestExecutionModeBackground) {
        if (config.redirectPolicy != TNLRequestRedirectPolicyDoRedirect) {
            NSString *message = @"The operation will execute in the background and follow all redirects however the operation's configuration specified a policy that differs.  Operation will continue by ignoring the policy and following redirects.";
            TNLLogWarning(@"%@", message);
            TNLAssertMessage(config.redirectPolicy == TNLRequestRedirectPolicyDoRedirect, @"%@", message);
        }
    }

    nextBlock();
}

static void _network_prepStep_applyGlobalHeadersToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    NSArray<id<TNLHTTPHeaderProvider>> *headerProviders = [TNLRequestOperationQueue allGlobalHeaderProviders];
    if (headerProviders.count > 0) {
        // Since HTTP headers are case-insensitive,
        // we want to use the setValue:forHTTPHeaderField:
        // for every single header to use the built in
        // case-insensitive behavior built into NSURLRequest

        // Pull out the dictionaries
        NSDictionary<NSString *, NSString *> *existingHeaders = self->_scratchURLRequest.allHTTPHeaderFields;
        NSMutableDictionary<NSString *, NSString *> *defaultHeaders = [[NSMutableDictionary alloc] init];
        NSMutableDictionary<NSString *, NSString *> *overrideHeaders = [[NSMutableDictionary alloc] init];

        NSURLRequest *immutableScratchRequest = [self->_scratchURLRequest copy];
        for (id<TNLHTTPHeaderProvider> headerProvider in headerProviders) {
            NSDictionary<NSString *, NSString *> *tmpDict;
            if ([headerProvider respondsToSelector:@selector(tnl_allDefaultHTTPHeaderFieldsForRequest:URLRequest:)]) {
                tmpDict = [headerProvider tnl_allDefaultHTTPHeaderFieldsForRequest:self->_originalRequest
                                                                        URLRequest:immutableScratchRequest];
                [defaultHeaders addEntriesFromDictionary:tmpDict];
            }
            if ([headerProvider respondsToSelector:@selector(tnl_allOverrideHTTPHeaderFieldsForRequest:URLRequest:)]) {
                tmpDict = [headerProvider tnl_allOverrideHTTPHeaderFieldsForRequest:self->_originalRequest
                                                                         URLRequest:immutableScratchRequest];
                [overrideHeaders addEntriesFromDictionary:tmpDict];
            }
        }

        // Clear the headers on the request to start
        self->_scratchURLRequest.allHTTPHeaderFields = nil;

        // 1) default headers
        [defaultHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [self->_scratchURLRequest setValue:obj forHTTPHeaderField:key];
        }];

        // 2) specified headers
        [existingHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [self->_scratchURLRequest setValue:obj forHTTPHeaderField:key];
        }];

        // 3) override headers
        [overrideHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [self->_scratchURLRequest setValue:obj forHTTPHeaderField:key];
        }];
    }

    nextBlock();
}

static void _network_prepStep_applyAcceptEncodingsToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);
    tnl_defer(nextBlock);

    // Do we do decoding?

    switch (self->_requestConfiguration.responseDataConsumptionMode) {
        case TNLResponseDataConsumptionModeStoreInMemory:
        case TNLResponseDataConsumptionModeChunkToDelegateCallback:
            break;
        default:
            // won't decode
            return;
    }

    switch (self->_requestConfiguration.executionMode) {
        case TNLRequestExecutionModeInApp:
        case TNLRequestExecutionModeInAppBackgroundTask:
            break;
        default:
            // won't decode
            return;
    }

    // Store the decoders that we'll use

    NSArray<id<TNLContentDecoder>> *additionalDecoders = self->_requestConfiguration.additionalContentDecoders;

    BOOL didSetAdditionalDecoders = NO;
    NSMutableSet<NSString *> *decoderTypes = [NSMutableSet setWithCapacity:additionalDecoders.count + 3];
    if ([NSURLSessionConfiguration tnl_URLSessionSupportsDecodingBrotliContentEncoding]) {
        [decoderTypes addObject:@"br"]; // supported by default on recent OSes
    }
    [decoderTypes addObject:@"gzip"]; // supported by default
    [decoderTypes addObject:@"deflate"]; // supported by default
    if (additionalDecoders.count > 0) {
        NSMutableDictionary<NSString *, id<TNLContentDecoder>> *decoders = [[NSMutableDictionary alloc] initWithCapacity:additionalDecoders.count];
        for (id<TNLContentDecoder> decoder in additionalDecoders) {
            NSString *decoderType = [[decoder tnl_contentEncodingType] lowercaseString];
            if (![decoderTypes containsObject:decoderType]) {
                [decoderTypes addObject:decoderType];
                decoders[decoderType] = decoder;
            }
        }

        if (decoders.count > 0) {
            self.additionalDecoders = [decoders copy];
            didSetAdditionalDecoders = YES;
        } else {
            self.additionalDecoders = nil;
        }
    } else {
        self.additionalDecoders = nil;
    }

    NSString *HTTPHeaderDecoderTypesString = [[self->_scratchURLRequest valueForHTTPHeaderField:@"Accept-Encoding"] lowercaseString];
    if (!HTTPHeaderDecoderTypesString) {

        // No Accept-Encoding set

        if (didSetAdditionalDecoders) {

            // Set the Accept-Encoding to our supported decoders

            NSArray<NSString *> *sortedDecoderTypes = [decoderTypes.allObjects sortedArrayUsingSelector:@selector(compare:)];
            HTTPHeaderDecoderTypesString = [sortedDecoderTypes componentsJoinedByString:@", "];
            [self->_scratchURLRequest setValue:HTTPHeaderDecoderTypesString forHTTPHeaderField:@"Accept-Encoding"];

        }

    }

    if (gTwitterNetworkLayerAssertEnabled && didSetAdditionalDecoders) {

        // A custom set of Accept-Encodings were provided... let's validate (but not fail)

        NSMutableSet<NSString *> *HTTPHeaderDecoderTypesSet = nil;
        NSArray<NSString *> *HTTPHeaderDecoderTypes = [HTTPHeaderDecoderTypesString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]];
        if (HTTPHeaderDecoderTypes.count) {
            HTTPHeaderDecoderTypesSet = [NSMutableSet setWithCapacity:(HTTPHeaderDecoderTypes.count / 2) + 1];
            for (NSString *decoderType in HTTPHeaderDecoderTypes) {
                NSArray<NSString *> *decoderTypeComponents = [decoderType componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"; "]];
                NSString *decoderTypeTrue = decoderTypeComponents.firstObject;
                if (decoderTypeTrue.length) {
                    if ([decoderType isEqualToString:@"*"]) {
                        // ballsy!  will take anything in response
                        TNLLogWarning(@"%@ has `Accept-Encoding: %@` - this can be overly accepting!", self->_originalRequest, HTTPHeaderDecoderTypesString);
                        return;
                    }
                    [HTTPHeaderDecoderTypesSet addObject:decoderTypeTrue];
                }
            }
        }

        NSMutableSet<NSString *> *diff = [HTTPHeaderDecoderTypesSet mutableCopy];
        [diff minusSet:decoderTypes];
        if (diff.count > 0) {
            NSArray<NSString *> *sortedDecoderTypes = [decoderTypes.allObjects sortedArrayUsingSelector:@selector(compare:)];
            NSString *decoderTypesString = [sortedDecoderTypes componentsJoinedByString:@", "];
            TNLLogWarning(@"%@ has `Accept-Encoding: %@` - but only has specified decoders for `%@`", self->_originalRequest, HTTPHeaderDecoderTypesString, decoderTypesString);
        }

    }
}

static void _network_prepStep_applyContentEncodingToScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    // Body to encode?
    NSData *body = self->_scratchURLRequest.HTTPBody;
    if (!body.length) {
        nextBlock();
        return;
    }

    // Encoder to encode with?
    id<TNLContentEncoder> encoder = self->_requestConfiguration.contentEncoder;
    if (!encoder) {
        nextBlock();
        return;
    }

    // If there's a preset "Content-Encoding", can we handle it?
    NSString *encoderType = [[encoder tnl_contentEncodingType] lowercaseString];
    NSString *HTTPHeaderEncoderType = [[self->_scratchURLRequest valueForHTTPHeaderField:@"Content-Encoding"] lowercaseString];
    if (HTTPHeaderEncoderType && ![HTTPHeaderEncoderType isEqualToString:encoderType]) {
        [self _network_fail:TNLErrorCreateWithCode(TNLErrorCodeRequestOperationRequestContentEncodingTypeMissMatch)];
        return;
    }

    // Jump to coding queue
    tnl_dispatch_async_autoreleasing(tnl_coding_queue(), ^{

        // Do encoding
        const uint64_t startMachTime = mach_absolute_time();
        NSError *encoderError;
        NSData *encodedData = [encoder tnl_encodeHTTPBody:body error:&encoderError];
        const NSTimeInterval encodeLatency = TNLComputeDuration(startMachTime, mach_absolute_time());
        const BOOL skipEncoding = (encoderError.code == TNLContentEncodingErrorCodeSkipEncoding) &&
                                  [encoderError.domain isEqualToString:TNLContentEncodingErrorDomain];

        // Back to network queue
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{

            // Error?
            if (!encodedData && !skipEncoding) {
                [self _network_fail:TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationRequestContentEncodingFailed, encoderError)];
                return;
            }

            // Success!
            if (skipEncoding) {
                self->_scratchURLRequest.HTTPBody = body;
                [self->_scratchURLRequest setValue:nil forHTTPHeaderField:@"Content-Encoding"];
            } else {
                const NSUInteger originalLength = body.length;
                const NSUInteger encodedLength = encodedData.length;
                self->_scratchURLRequest.HTTPBody = encodedData;
                [self->_scratchURLRequest setValue:encoderType forHTTPHeaderField:@"Content-Encoding"];
                self->_scratchURLRequestEncodeLatency = encodeLatency;
                self->_scratchURLRequestOriginalBodyLength = (SInt64)originalLength;
                self->_scratchURLRequestEncodedBodyLength = (SInt64)encodedLength;
#if DEBUG
                const double ratio = (encodedLength) ? (double)originalLength / (double)encodedLength : 0;
                TNLLogDebug(@"%@ compression ratio: %f", self->_scratchURLRequest.URL, ratio);
#endif
            }

            nextBlock();
        });
    });
}

static void _network_prepStep_sanitizeHostForScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    NSString *host = self->_scratchURLRequest.URL.host;
    self->_hostSanitizer = (self->_requestConfiguration.skipHostSanitization) ? nil : [TNLGlobalConfiguration sharedInstance].hostSanitizer;

    if (self->_hostSanitizer) {
        [self->_hostSanitizer tnl_host:host
           wasEncounteredForURLRequest:[self->_scratchURLRequest copy]
                            asRedirect:NO
                            completion:^(TNLHostSanitizerBehavior behavior, NSString *newHost) {
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                TNLAssert([host isEqualToString:self->_scratchURLRequest.URL.host]);
                NSError *error = nil;
                const TNLHostReplacementResult hostReplacementResult = [self->_scratchURLRequest tnl_replaceURLHost:newHost
                                                                                                           behavior:behavior
                                                                                                              error:&error];
                if (TNLHostReplacementResultSuccess == hostReplacementResult) {
                    [self _network_notifySanitizedHost:host toHost:newHost];
                }

                if (error) {
                    [self _network_fail:error];
                } else {
                    nextBlock();
                }
            });
        }];
    } else {
        nextBlock();
    }
}

static void _network_prepStep_authorizeScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    id<TNLRequestAuthorizer> authorizer = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:authorizeURLRequest:completion:);

    if (!authorizer || ![authorizer respondsToSelector:callback]) {
        nextBlock();
        return;
    }

    tnl_dispatch_barrier_async_autoreleasing(self->_callbackQueue, ^{
        NSString *tag = TAG_FROM_METHOD(authorizer, @protocol(TNLRequestAuthorizer), callback);
        [self _updateTag:tag];
        [authorizer tnl_requestOperation:self
                     authorizeURLRequest:[self->_scratchURLRequest copy]
                              completion:^(NSString *authHeader, NSError *error) {
            [self _clearTag:tag];

            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                if (![self _network_isPreparing]) {
                    return;
                }

                if (error) {
                    [self _network_fail:TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationFailedToAuthorizeRequest, error)];
                    return;
                }

                if (authHeader) {
                    [self->_scratchURLRequest setValue:(authHeader.length > 0) ? authHeader : nil
                                    forHTTPHeaderField:@"Authorization"];
                }
                nextBlock();
            });
        }];
    });
}

static void _network_prepStep_cementScratchURLRequest(TNLRequestOperation * __nullable const self, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert([self _network_isPreparing]);

    self.hydratedURLRequest = self->_scratchURLRequest;
    self->_scratchURLRequest = nil;

    nextBlock();
}

#pragma mark NSOperation helpers

- (void)_network_prepareToConnectThenConnect:(BOOL)isRetry
{
    [self _network_prepareRequestStep:0 isRetry:isRetry];
}

- (void)_network_connect:(BOOL)isRetry
{
    TNLAssert([self _network_isPreparing]);

    TNLAssertMessage(self.URLSessionTaskOperation == nil, @"Already have a TNLURLSessionTaskOperation? state = %@", TNLRequestOperationStateToString(self.state));

    // Do not update the `.state` here.
    // The `.URLSessionTaskOperation` will update to `TNLRequestOperationStateStarting` once it starts
    // (which may be delayed by 503 backoffs).

    [self.requestOperationQueue findURLSessionTaskOperationForRequestOperation:self
                                                                      complete:^(TNLURLSessionTaskOperation *taskOp) {
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            [self _network_startURLSessionTaskOperation:taskOp isRetry:isRetry];
        });
    }];
}

- (void)_network_startURLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                                      isRetry:(BOOL)isRetry
{
    if ([self _network_hasFailedOrFinished]) {
        return;
    }

    self.URLSessionTaskOperation = taskOp;

    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:readyToEnqueueUnderlyingNetworkingOperation:enqueueBlock:);
    if (![eventHandler respondsToSelector:callback]) {
        [taskOp enqueueToOperationQueueIfNeeded:self.requestOperationQueue];
        return;
    }

    tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
        NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
        [self _updateTag:tag];
        [eventHandler tnl_requestOperation:self
                      readyToEnqueueUnderlyingNetworkingOperation:isRetry
                      enqueueBlock:^(NSArray<NSOperation *> *dependencies) {
            [self _clearTag:tag];
            // add dependencies synchronously with callback
            if (dependencies) {
                TNLLogDebug(@"Added dependencies to %@: %@", taskOp, dependencies);
                for (NSOperation *op in dependencies) {
                    [taskOp addDependency:op];
                }
            }
            // dispatch to network queue to start the op
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                [taskOp enqueueToOperationQueueIfNeeded:self.requestOperationQueue];
            });
        }];
    });
}

- (void)_network_fail:(NSError *)error
{
    [self _network_prepareToStart]; // in case we fail before we start

    if ([self _network_hasFailed]) {
        return;
    }

    if (!_backgroundFlags.didStart) {
        return;
    }

    if ([self _network_isStateFinished]) {
        // something else failed first, abort this subsequent attempt to fail
        return;
    }

    TNLAssert(error != nil);
    BOOL isCancel = NO;
    BOOL isTerminal = NO;

    if ([error.domain isEqualToString:TNLErrorDomain]) {
        isTerminal = TNLErrorCodeIsTerminal(error.code);
        isCancel = (error.code == TNLErrorCodeRequestOperationCancelled);
    }

    if (isTerminal) {
        self.terminalErrorOverride = error;
    }

    TNLResponseInfo *info = [[TNLResponseInfo alloc] initWithFinalURLRequest:self.currentURLRequest
                                                                 URLResponse:self.currentURLResponse
                                                                      source:self.responseSource
                                                                        data:nil
                                                          temporarySavedFile:nil];

    TNLAttemptMetaData *metadata;
    NSURLSessionTaskMetrics *taskMetrics;
    TNLURLSessionTaskOperation *URLSessionTaskOperation = self.URLSessionTaskOperation;
    if (URLSessionTaskOperation) {
        metadata = [URLSessionTaskOperation network_metaDataWithLowerCaseHeaderFields:info.allHTTPHeaderFieldsWithLowerCaseKeys];
        taskMetrics = [URLSessionTaskOperation network_taskMetrics];
    } else {
        metadata = (TNLAttemptMetaData * __nonnull)nil;
        taskMetrics = nil;
    }

    TNLResponse *response = [self _network_finalizeResponseWithInfo:info
                                                      responseError:error
                                                           metadata:metadata
                                                        taskMetrics:taskMetrics];

    if ([self _network_isStateFinished]) {
        TNLAssertNever();
        return;
    }

    [self _network_transitionToState:(isCancel) ? TNLRequestOperationStateCancelled : TNLRequestOperationStateFailed
                 withAttemptResponse:response];

    // discard the task operation at the end so all internal states can be updated first before disassociating with the associated task operation
    self.URLSessionTaskOperation = nil;
}

#pragma mark NSOperation

- (void)_network_retryWithOldResponse:(TNLResponse *)oldResponse
                  retryPolicyProvider:(nullable id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
{
    if ([self _network_hasFailedOrFinished]) {
        return;
    }

    TNLAssertMessage(TNLRequestOperationStateWaitingToRetry == atomic_load(&_state), @"Actual state is %@", TNLRequestOperationStateToString(atomic_load(&_state)));
    self.downloadProgress = 0.0;
    self.uploadProgress = 0.0;
    [self _network_start:YES /*isRetry*/];
    if (!_backgroundFlags.silentStart) {
        SEL callback = @selector(tnl_requestOperation:didStartRetryFromResponse:);
        if ([retryPolicyProvider respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_RetryPolicyProviderQueue(retryPolicyProvider), ^{
                NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), callback);
                [self _updateTag:tag];
                [retryPolicyProvider tnl_requestOperation:self
                                didStartRetryFromResponse:oldResponse];
                [self _clearTag:tag];
            });
        }
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        callback = @selector(tnl_requestOperation:didStartRetryFromResponse:policyProvider:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperation:self
                         didStartRetryFromResponse:oldResponse
                                    policyProvider:retryPolicyProvider];
                [self _clearTag:tag];
            });
        }
    }
}

- (void)_network_prepareToStart
{
    if (!_backgroundFlags.didStart) {
        if (!_backgroundFlags.didPrep) {
            id<TNLRequestDelegate> delegate = self.internalDelegate;

            // Get the callback queue

            _callbackQueue = [delegate respondsToSelector:@selector(tnl_delegateQueueForRequestOperation:)] ? [delegate tnl_delegateQueueForRequestOperation:self] :                                 nil;
            if (!_callbackQueue) {
                _callbackQueue = _RequestOperationDefaultCallbackQueue();
            }

            // Get the completion queue

            _completionQueue = [delegate respondsToSelector:@selector(tnl_completionQueueForRequestOperation:)] ? [delegate tnl_completionQueueForRequestOperation:self] : nil;
            if (!_completionQueue) {
                _completionQueue = dispatch_get_main_queue();
            }

            _backgroundFlags.didPrep = YES;
        }
    }
}

- (void)_network_start:(BOOL)isRetry
{
    if ([self _network_hasFailedOrFinished]) {
        // might have been pre-emptively cancelled or failed
        return;
    }

    // Start a background task to keep things running even in the background
    if (TNLRequestExecutionModeInAppBackgroundTask == _requestConfiguration.executionMode) {
        [self _network_startBackgroundTask]; // noop in macOS
    }

    [self _network_transitionToState:TNLRequestOperationStatePreparingRequest
                 withAttemptResponse:nil];
    [self _network_startAttemptTimeoutTimer:_requestConfiguration.attemptTimeout];

    // add to queue in case there are existing executions backed up
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_prepareToConnectThenConnect:isRetry];
    });
}

- (void)_network_cleanupAfterComplete
{
    [self _network_invalidateRetry];
    [self _network_invalidateOperationTimeoutTimer];
}

#pragma mark Private Methods

- (void)_network_transitionToState:(TNLRequestOperationState)state
               withAttemptResponse:(nullable TNLResponse *)attemptResponse
{
    if ([self _network_isStateFinished]) {
        return;
    }

    const TNLRequestOperationState oldState = atomic_load(&_state);
    if (oldState != state) {
        if (TNLRequestOperationStateRunning == state && TNLRequestOperationStateStarting != oldState) {
            return;
        }

        if (gTwitterNetworkLayerAssertEnabled) {
            switch (state) {
                case TNLRequestOperationStateIdle:
                    TNLAssertNever();
                    break;
                case TNLRequestOperationStatePreparingRequest:
                    TNLAssert(TNLRequestOperationStateIdle == oldState || TNLRequestOperationStateWaitingToRetry == oldState);
                    TNLAssert(!attemptResponse);
                    break;
                case TNLRequestOperationStateStarting:
                case TNLRequestOperationStateRunning:
                    TNLAssertMessage(oldState < state, @"oldState (%zd) < newState (%zd)", (long) oldState, (long) state);
                    TNLAssert(!attemptResponse);
                    break;
                case TNLRequestOperationStateWaitingToRetry:
                    TNLAssert(!TNLRequestOperationStateIsFinal(oldState));
                    TNLAssert(!attemptResponse);
                    break;
                case TNLRequestOperationStateCancelled:
                case TNLRequestOperationStateFailed:
                case TNLRequestOperationStateSucceeded:
                    TNLAssert(!TNLRequestOperationStateIsFinal(oldState));
                    TNLAssert(attemptResponse != nil);
                    break;
            }

            if (oldState == TNLRequestOperationStateWaitingToRetry) {
                TNLAssert((TNLRequestOperationStateIsFinal(state) || TNLRequestOperationStatePreparingRequest == state));
            }
        }

        if (TNLRequestOperationStateIsFinal(state)) {
            // Finished the attempt
            // we are done with the attempt timer (for now)
            [self _network_invalidateAttemptTimeoutTimer];
        }

        // either start the retry or complete the state transition
        [self _network_attemptRetryDuringTransitionFromState:oldState
                                                     toState:state
                                         withAttemptResponse:attemptResponse];
    }
}

- (void)_network_completeTransitionFromState:(TNLRequestOperationState)oldState
                                     toState:(TNLRequestOperationState)state
                         withAttemptResponse:(nullable TNLResponse *)attemptResponse
{
    // KVO - Prep

    BOOL cancelDidChange = NO;
    BOOL finishedDidChange = NO;
    BOOL executingDidChange = NO;
    if (TNLRequestOperationStateIsFinal(state)) {
        cancelDidChange = (TNLRequestOperationStateCancelled == state);
        finishedDidChange = YES;
        executingDidChange = YES;
        if (!self->_backgroundFlags.didStart) {
            TNLLogError(@"%@ changed stated to be final before being started!\n%@", NSStringFromClass([self class]), self.hydratedURLRequest);
        }
        TNLAssert(_backgroundFlags.didStart);
        TNLAssert(attemptResponse != nil);
    } else if (TNLRequestOperationStateIdle == oldState) {
        executingDidChange = YES;
    }

    // Metrics

    [self _network_updateMetricsFromState:oldState
                                  toState:state
                      withAttemptResponse:attemptResponse];
    if (attemptResponse) {
        TNLAttemptCompleteDisposition disposition = TNLAttemptCompleteDispositionCompleting;
        if (TNLRequestOperationStateWaitingToRetry == state) {
            disposition = TNLAttemptCompleteDispositionRetrying;
        }
        [self _network_didCompleteAttemptWithResponse:attemptResponse
                                          disposition:disposition];
    }

    // KVO - Transition

    if (finishedDidChange) {
        [self willChangeValueForKey:@"isFinished"];
    }
    if (cancelDidChange) {
        [self willChangeValueForKey:@"isCancelled"];
    }
    if (executingDidChange) {
        [self willChangeValueForKey:@"isExecuting"];
    }

    [self setState:state async:NO];

    if (executingDidChange) {
        [self didChangeValueForKey:@"isExecuting"];
    }
    if (cancelDidChange) {
        [self didChangeValueForKey:@"isCancelled"];
    }
    if (finishedDidChange) {
        [self didChangeValueForKey:@"isFinished"];
    }

    // Log the transition

    TNLLogLevel level = TNLLogLevelDebug;
    if (TNLRequestOperationStateIsFinal(state)) {
        level = (TNLRequestOperationStateFailed == state) ? TNLLogLevelError : TNLLogLevelInformation;
    }
    TNLLog(level, @"%@%@: %@ -> %@\n%@",
           self,
           self.URLSessionTaskOperation,
           TNLRequestOperationStateToString(oldState),
           TNLRequestOperationStateToString(state),
           [self _createLogContextStringForState:state withResponse:attemptResponse]);

    // Delegate callback

    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:didTransitionFromState:toState:);
    if ([eventHandler respondsToSelector:callback]) {
        tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
            NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
            [self _updateTag:tag];
            [eventHandler tnl_requestOperation:self
                        didTransitionFromState:oldState
                                       toState:state];
            [self _clearTag:tag];
        });
    }

    // Completion

    if (finishedDidChange) {
        // have aggressive assert here, whether TNL asserts are enabled or not
        if (nil == attemptResponse) {
            __TNLAssertTriggering();
        }
#if NS_BLOCK_ASSERTIONS
        assert(attemptResponse != nil);
#else
        TNLCAssert(attemptResponse != nil, @"assertion failed: cannot finish a %@ with a nil TNLResponse!", NSStringFromClass([self class]));
#endif

        [self.requestOperationQueue operation:self
                      didCompleteWithResponse:attemptResponse];
        [self _network_completeWithResponse:attemptResponse];
    }
}

- (void)_network_updateMetricsFromState:(TNLRequestOperationState)oldState
                                toState:(TNLRequestOperationState)newState
                    withAttemptResponse:(nullable TNLResponse *)attemptResponse
{
    NSDate *dateNow = [NSDate date];
    const uint64_t machTime = mach_absolute_time();
    if (TNLRequestOperationStateStarting == newState) {
        if (!_backgroundFlags.silentStart) {
            // get the hydrated URL request we will be passing to the NSURLSessionTask in the TNLURLSessionTaskOperation
            // ... NOT the currentURLRequest since that won't have been applied yet
            NSURLRequest *request = self.hydratedURLRequest;
            if (!request) {
                // we could be going through a transition to an early failure state during/before hydration,
                // so we'll use some fallbacks to find the best matching request for populating the metrics.

                // try the incomplete scratch request
                request = [_scratchURLRequest copy];
                if (!request) {
                    // no scratch request, try the hydrated request
                    request = TNLRequestToNSURLRequest(self.hydratedRequest, nil /*config*/, NULL /*errorOut*/);
                    if (!request) {
                        // no hydrated request either, try just the original request
                        request = TNLRequestToNSURLRequest(self.originalRequest, nil /*config*/, NULL /*errorOut*/);
                    }
                }
            }
            TNLAssertMessage(request != nil, @"must have a request by time Starting state happens");
            [self willChangeValueForKey:@"attemptCount"];
            if (_metrics.attemptCount == 0) {
                [_metrics addInitialStartWithDate:dateNow
                                         machTime:machTime
                                          request:request];
                [self.requestOperationQueue operation:self
                           didStartAttemptWithMetrics:_metrics.attemptMetrics.lastObject];
            } else {
                // TODO:[nobrien] - if we break apart redirect attempts to own in TNL instead of the NSURLSessionTask,
                // this will need key off what is causing the state to move to Starting (Retry vs Redirect for example)
                [self willChangeValueForKey:@"retryCount"];
                [_metrics addRetryStartWithDate:dateNow
                                       machTime:machTime
                                        request:request];
                [self.requestOperationQueue operation:self
                           didStartAttemptWithMetrics:_metrics.attemptMetrics.lastObject];
                [self didChangeValueForKey:@"retryCount"];
            }
            [self didChangeValueForKey:@"attemptCount"];
        } else {
            TNLAssert(_metrics.attemptCount > 0);
        }
    } else if (TNLRequestOperationStateWaitingToRetry == newState || TNLRequestOperationStateIsFinal(newState)) {
        // We'll have 2 copies of metrics to deal with here
        // 1) is our running metrics which can keep getting extended
        // 2) is our TNLResponse for this attempt
        // Update both copies
        NSHTTPURLResponse *response = self.currentURLResponse;
        NSError *error = self.error ?: attemptResponse.operationError;
        [_metrics addEndDate:dateNow
                    machTime:machTime
                    response:response
              operationError:error];
        TNLResponseMetrics *attemptMetrics = attemptResponse.metrics;
        [attemptMetrics addEndDate:dateNow
                          machTime:machTime
                          response:response
                    operationError:error];
        if (TNLRequestOperationStateIsFinal(newState)) {
            if (attemptMetrics.completeDate) {
                [_metrics setCompleteDate:attemptMetrics.completeDate
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                                 machTime:attemptMetrics.completeMachTime];
#pragma clang diagnostic pop
            } else {
                [_metrics setCompleteDate:dateNow machTime:machTime];
                [attemptMetrics setCompleteDate:dateNow machTime:machTime];
            }
        }
    }
}

- (void)_network_didCompleteAttemptWithResponse:(TNLResponse *)response
                                    disposition:(TNLAttemptCompleteDisposition)disposition
{
    if (response) {
        [self.requestOperationQueue operation:self
                           didCompleteAttempt:response
                                  disposition:disposition];

        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didCompleteAttemptWithResponse:disposition:);
        if ([eventHandler respondsToSelector:callback]) {
            tnl_dispatch_barrier_async_autoreleasing(_callbackQueue, ^{
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                [self _updateTag:tag];
                [eventHandler tnl_requestOperation:self
                    didCompleteAttemptWithResponse:response
                                       disposition:disposition];
                [self _clearTag:tag];
            });
        }
    }
}

- (void)_network_completeWithResponse:(TNLResponse *)response
{
    [self _network_prepareToStart]; // ensure we have variables in case we finished before we started
    [self _network_cleanupAfterComplete];
    [self.requestOperationQueue clearQueuedRequestOperation:self];

    TNLAssert(nil != response);
    TNLAssert(_uploadProgress <= 1.0f);
    TNLAssert(_downloadProgress <= 1.0f);
    self.internalFinalResponse = response;

    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:didCompleteWithResponse:);
    const BOOL hasCompletionCallback = [eventHandler respondsToSelector:callback];
    dispatch_block_t block = ^{
        if (hasCompletionCallback) {
            NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
            [self _updateTag:tag];
            [eventHandler tnl_requestOperation:self
                       didCompleteWithResponse:response];
            [self _clearTag:tag];
        }
        [self _finalizeCompletion]; // finalize from the completion queue
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            [self _network_endBackgroundTask];
        });
    };

    if (_callbackQueue == _completionQueue) {
        tnl_dispatch_barrier_async_autoreleasing(_completionQueue, block);
    } else {
        // dispatch to callback queue to flush the callback queue
        dispatch_barrier_async(_callbackQueue, ^{
            // dispatch to completion queue for completion
            tnl_dispatch_barrier_async_autoreleasing(self->_completionQueue, block);
        });
    }
}

- (void)_finalizeCompletion
{
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&_didCompleteFinishedCallback, true);
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (NSString *)_createLogContextStringForState:(TNLRequestOperationState)state
                                 withResponse:(nullable TNLResponse *)response TNL_OBJC_DIRECT
{
    NSMutableDictionary *logContext = [NSMutableDictionary dictionary];
    TNLResponseMetrics *metrics = response.metrics;

    const BOOL logVerboseEnabled = TNLLogVerboseEnabled();
#if DEBUG
    const BOOL logHeaders = logVerboseEnabled;
    BOOL logAdvancedInfo = logVerboseEnabled;
#else
    const BOOL logHeaders = (TNLRequestOperationStateFailed == state) && logVerboseEnabled;
    BOOL logAdvancedInfo = (self.attemptCount > 1 || metrics.totalDuration > 1.0) && logVerboseEnabled;
#endif

    id<TNLRequest> request = self.hydratedRequest ?: self.originalRequest;
    NSURL *url = [request respondsToSelector:@selector(URL)] ? [(id)request URL] : nil;
    if (url) {
        logContext[@"url"] = url;
    }

    NSURL *finalURL = response.info.finalURL;
    if (finalURL && ![finalURL isEqual:url]) {
        logContext[@"finalURL"] = finalURL;
    }

    NSError *error = self.error ?: response.operationError;
    if (error) {
        logAdvancedInfo = logVerboseEnabled;
        NSString *errorDescription = [error description];
        if (url) {
            // errors can often have the url within multiple times;
            // to reduce verbosity, exclude url
            errorDescription = [errorDescription stringByReplacingOccurrencesOfString:url.absoluteString
                                                                           withString:@"::url"];
        }
        if (finalURL) {
            // errors can often have the finalURL within multiple times;
            // to reduce verbosity, exclude url
            errorDescription = [errorDescription stringByReplacingOccurrencesOfString:finalURL.absoluteString
                                                                           withString:@"::finalURL"];
        }
        logContext[@"error"] = errorDescription;
    }

    if (TNLRequestOperationStateStarting != state) {
        NSHTTPURLResponse *URLResponse = response.info.URLResponse ?: self.currentURLResponse;
        if (URLResponse) {
            logContext[@"statusCode"] = @(URLResponse.statusCode);
            if (URLResponse.statusCode != TNLHTTPStatusCodeOK) {
                logAdvancedInfo = logVerboseEnabled;
            }
            if (logAdvancedInfo) {
                NSString *statusCodeString = [NSHTTPURLResponse localizedStringForStatusCode:URLResponse.statusCode];
                if (statusCodeString.length > 0) {
                    logContext[@"statusCodeString"] = statusCodeString;
                }
            }
        }
    }

    if (logAdvancedInfo) {
        logContext[@"hydrated"] = @(self.hydratedRequest == request);
    }

    if (TNLRequestOperationStateIsFinal(state)) {
        logContext[@"durationTotal"] = @(metrics.totalDuration);
    }

    if (logAdvancedInfo) {
        if (TNLRequestOperationStateIsActive(state) || TNLRequestOperationStateIsFinal(state)) {
            logContext[@"countAttempt"] = @(self.attemptCount);
            logContext[@"countRetry"] = @(self.retryCount);
        }

        if (TNLRequestOperationStateIsFinal(state)) {
            if (TNLRequestOperationStateSucceeded != state) {
                logContext[@"progressUp"] = @(self.uploadProgress);
                logContext[@"progressDown"] = @(self.downloadProgress);
            } else {
                long long contentLength = [response.info.URLResponse tnl_expectedResponseBodySize];
                if (contentLength > 0) {
                    logContext[@"rx-contentLength"] = @(contentLength);
                }
                contentLength = [[response.info.finalURLRequest valueForHTTPHeaderField:@"Content-Length"] longLongValue];
                if (contentLength > 0) {
                    logContext[@"tx-contentLength"] = @(contentLength);
                }
            }

            NSString *contentEncoding = [response.info.URLResponse tnl_contentEncoding];
            if (contentEncoding) {
                logContext[@"rx-contentEncoding"] = contentEncoding;
            }

            contentEncoding = [response.info.finalURLRequest valueForHTTPHeaderField:@"Content-Encoding"];
            if (contentEncoding) {
                logContext[@"tx-contentEncoding"] = contentEncoding;
            }

            if (logHeaders) {
                logContext[@"requestHeaders"] = _redactHeaderFields([response.info.finalURLRequest allHTTPHeaderFields]);
                logContext[@"responseHeaders"] = _redactHeaderFields([response.info.URLResponse allHeaderFields]);
            }

            logContext[@"durationQueued"] = @(metrics.queuedDuration);

            if ([NSURLSessionConfiguration tnl_URLSessionCanUseTaskTransactionMetrics]) {
                NSURLSessionTaskTransactionMetrics *taskMetrics = metrics.attemptMetrics.lastObject.taskTransactionMetrics;
                if (taskMetrics) {
                    NSDictionary *taskMetricsDictionary = [taskMetrics tnl_dictionaryValue];
                    if (taskMetricsDictionary) {
                        logContext[@"lastTaskMetrics"] = taskMetricsDictionary;
                    }
                }
            }
        }
    }

    return [logContext description];
}

static NSDictionary<NSString *, NSString *> *_redactHeaderFields(NSDictionary *headerFields)
{
    id<TNLLogger> logger = gTNLLogger;
    if (!logger) {
        return [headerFields copy];
    }

    NSMutableDictionary *redactedHeaderFields = [[NSMutableDictionary alloc] init];

    [headerFields enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        TNLAssert([key isKindOfClass:[NSString class]]);
        if ([logger tnl_shouldRedactHTTPHeaderField:key]) {
            redactedHeaderFields[key] = kRedactedKeyValue;
        } else {
            redactedHeaderFields[key] = value;
        }
    }];

    return [redactedHeaderFields copy];
}

- (TNLResponse *)_network_finalizeResponseWithInfo:(TNLResponseInfo *)responseInfo
                                     responseError:(nullable NSError *)responseError
                                          metadata:(nullable TNLAttemptMetaData *)metadata
                                       taskMetrics:(nullable NSURLSessionTaskMetrics *)taskMetrics
{
    [self _network_applyEncodingMetricsToInfo:responseInfo withMetaData:metadata];
    [_metrics addMetaData:metadata taskMetrics:taskMetrics];

    // Capture any methods we are in when the timeout occurred
    if ([responseError.domain isEqualToString:TNLErrorDomain]) {
        switch (responseError.code) {
            case TNLErrorCodeRequestOperationAttemptTimedOut:
            case TNLErrorCodeRequestOperationIdleTimedOut:
            case TNLErrorCodeRequestOperationOperationTimedOut:
            case TNLErrorCodeRequestOperationCallbackTimedOut:
            {
                NSArray *tags = [_callbackTagStack copy];
                uint64_t mach_tagTime = _mach_callbackTagTime;
                if (tags.count > 0) {
                    NSMutableDictionary *userInfo = [responseError.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
                    userInfo[TNLErrorTimeoutTagsKey] = tags;
                    userInfo[@"timeoutTagDuration"] = @(TNLAbsoluteToTimeInterval(mach_absolute_time() - mach_tagTime));
                    userInfo[@"operationId"] = @(self.operationId);
                    responseError = [NSError errorWithDomain:responseError.domain
                                                        code:responseError.code
                                                    userInfo:userInfo];
                    TNLLogError(@"%@", responseError);
                    if (responseError.code == TNLErrorCodeRequestOperationCallbackTimedOut && [TNLGlobalConfiguration sharedInstance].shouldForceCrashOnCloggedCallback) {

                        NSException *exception = [NSException exceptionWithName:@"ForceCrashOnCloggedCallback"
                                                                         reason:@"A callback was clogged!"
                                                                       userInfo:@{ @"error" : responseError }];

#if DEBUG
                        if (TNLIsDebuggerAttached()) {
                            // don't throw an exception when debugging, a breakpoint can easily cause this
                            TNLLogWarning(@"Debugger attached, not throwing exception: %@, %@\n%@", exception, responseError, [NSThread callStackSymbols]);
                            break;
                        }
#endif

                        // Crash on the main thread since crashing on this TNL background thread offers no value in stack trace and could be misunderstood
                        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
                            @throw exception;
                        });

                    }
                }
                break;
            }
            default:
                break;
        }
    }

    // TODO[nobrien]: this is messy... having a response that has to be further manipulated downstream. FIX-ME
    // Also, this might not the best place to create the response with the defined responseClass

    TNLResponseMetrics *metrics = [_metrics deepCopyAndTrimIncompleteAttemptMetrics:NO];
    TNLResponse *response = [self.responseClass responseWithRequest:_originalRequest
                                                     operationError:responseError
                                                               info:responseInfo
                                                            metrics:metrics];
    TNLAssert(response != nil);
    return response;
}

- (void)_network_applyEncodingMetricsToInfo:(TNLResponseInfo *)responseInfo
                               withMetaData:(nullable TNLAttemptMetaData *)metadata
{
    if (_scratchURLRequestOriginalBodyLength > 0) {
        NSString *contentEncoding = [responseInfo.finalURLRequest valueForHTTPHeaderField:@"Content-Encoding"];
        if (contentEncoding) {
            metadata.requestContentLength = _scratchURLRequestEncodedBodyLength;
            metadata.requestOriginalContentLength = _scratchURLRequestOriginalBodyLength;
            metadata.requestEncodingLatency = _scratchURLRequestEncodeLatency;
        }
    }
}

#pragma mark Attempt Retry

- (BOOL)_network_shouldAttemptRetryDuringTransitionFromState:(TNLRequestOperationState)oldState
                                                     toState:(TNLRequestOperationState)state
                                         withAttemptResponse:(nullable TNLResponse *)attemptResponse
{
    if (!TNLRequestOperationStateIsFinal(state)) {
        return NO;
    }

    TNLAssert(attemptResponse != nil);
    if (!attemptResponse) {
        return NO;
    }

    if (TNLRequestOperationStateCancelled == state) {
        return NO;
    }

    if ([self _network_hasFailed]) {
        return NO;
    }

    if (TNLRequestOperationStateSucceeded == state) {
        if (TNLHTTPStatusCodeIsSuccess(attemptResponse.info.statusCode)) {
            // Can retry on non-defitive HTTP 2xx
            return !TNLHTTPStatusCodeIsDefinitiveSuccess(attemptResponse.info.statusCode);
        }
    } else if ([attemptResponse.operationError.domain isEqualToString:TNLErrorDomain]) {
        // TNL error encountered...

        // if we have a callback timeout caused by a delegate/retry-policy callback timing out, we should NOT retry
        if (attemptResponse.operationError.code == TNLErrorCodeRequestOperationCallbackTimedOut) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)_network_shouldForciblyRetryInvalidatedURLSessionRequestWithAttemptResponse:(TNLResponse *)attemptResponse
{
    TNLAssert([attemptResponse.operationError.domain isEqualToString:TNLErrorDomain] && attemptResponse.operationError.code == TNLErrorCodeRequestOperationURLSessionInvalidated);

    /*
     The session was invalidated.
     There is a rare race condition that can have a session invalidate as a new
     TNLURLSessionTaskOperation starts with that same session.
     The race condition is within NSURLSession itself and cannot be mitigated.
     Essentially, it appears as though the NSURL Framework maintains a pool of reuseable
     NSURLSessionInternal objects that are reused when a session is generated with the same
     configuration as an existing NSURLSessionInternal object.
     However, if the internal session will asynchronously be invalidated when its parent
     NSURLSession is invalidated, the removal of the object from the pool will also be async leaving
     a window of opportunity for a caller to request a new NSURLSession which will evaluate to an
     NSURLSessionInternal that is in the pool BUT has already been invalidated so any requests going
     to that new session will fail due to the session being invalid.
     This forcible retry will address this issue by identifying symptoms of when this race condition
     happens.
     This scenario is most likely to be exacerbated when the delay of a retry policy that kicks in
     is immediate and there are no other outstanding requests using the same underlying NSURLSession.
     This is because the retry will immediately go and attempt to use a new NSURLSession, but the
     underlying NSURLSessionInternal object will be used despite being invalid (or soon to become
     invalid).
     An additional measure that is in place is that the minimum delay before a retry is 0.1 seconds.
     We can safely kick off an immediate retry if:
         1) we weren't canceled (can't end up in here if Cancelled == state, so that's given)
         2) we didn't get a URL response yet
         3) the attempt was shorter than 1 second (which is a generous amount of time)
         4) we haven't already retried 4 times
     */

    const unsigned int maxInvalidSessionRetryCount = 4;
    TNLStaticAssert(maxInvalidSessionRetryCount < 0b1111, Max_Invalid_Session_Retry_Count_must_be_within_4_bits);
    const NSTimeInterval latestAttemptDuration = TNLComputeDuration(
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                                                                    attemptResponse.metrics.currentAttemptStartMachTime,
#pragma clang diagnostic pop
                                                                    mach_absolute_time());
    const BOOL forciblyRetry = (attemptResponse.info.URLResponse == nil) &&
                               (latestAttemptDuration < 1.0) &&
                               (_backgroundFlags.invalidSessionRetryCount < maxInvalidSessionRetryCount);
    TNLLogWarning(@"Encountered a session invalidation error, %@ retrying.\nError: %@", (forciblyRetry) ? @"" : @" not", attemptResponse.operationError);
    return forciblyRetry;
}

- (void)_network_forciblyRetryInvalidatedURLSessionRequestWithAttemptResponse:(TNLResponse *)attemptResponse
{
    if (_cachedCancelError) {
        [self _network_fail:_cachedCancelError];
    } else {
        _backgroundFlags.invalidSessionRetryCount++;
        self.URLSessionTaskOperation = nil;
        _backgroundFlags.silentStart = 1;
        [self _network_transitionToState:TNLRequestOperationStateWaitingToRetry
                     withAttemptResponse:nil];
        [self _network_startRetryWithDelay:MIN_TIMER_INTERVAL
                               oldResponse:attemptResponse
                       retryPolicyProvider:nil];
        // don't need to end the background task here since we are triggering
        // the retry in order to circumvent a race condition that causes a failure,
        // not actually retrying after a legitimate failure that could be of any
        // duration.
    }
}

- (void)_network_attemptRetryDuringTransitionFromState:(TNLRequestOperationState)oldState
                                               toState:(TNLRequestOperationState)state
                                   withAttemptResponse:(nullable TNLResponse *)attemptResponse
{
    if (_backgroundFlags.inRetryCheck) {
        return;
    }

    const BOOL shouldAttemptRetry = [self _network_shouldAttemptRetryDuringTransitionFromState:oldState
                                                                                       toState:state
                                                                           withAttemptResponse:attemptResponse];

    if (shouldAttemptRetry && [attemptResponse.operationError.domain isEqualToString:TNLErrorDomain] && attemptResponse.operationError.code == TNLErrorCodeRequestOperationURLSessionInvalidated) {
        // Invalidated session, we have special logic for this case
        if ([self _network_shouldForciblyRetryInvalidatedURLSessionRequestWithAttemptResponse:attemptResponse]) {
            [self _network_forciblyRetryInvalidatedURLSessionRequestWithAttemptResponse:attemptResponse];
            return;
        }
    }

    const id<TNLRequestRetryPolicyProvider> retryPolicyProvider = _requestConfiguration.retryPolicyProvider;
    if (!shouldAttemptRetry || !retryPolicyProvider || ![retryPolicyProvider respondsToSelector:@selector(tnl_shouldRetryRequestOperation:withResponse:)]) {
        // early check, not going to retry
        [self _network_completeTransitionFromState:oldState
                                           toState:state
                               withAttemptResponse:attemptResponse];
        return;
    }

    [self _network_retryDuringTransitionFromState:oldState
                                          toState:state
                              withAttemptResponse:attemptResponse
                              retryPolicyProvider:retryPolicyProvider];
}

- (void)_network_retryDuringTransitionFromState:(TNLRequestOperationState)oldState
                                        toState:(TNLRequestOperationState)state
                            withAttemptResponse:(TNLResponse *)attemptResponse
                            retryPolicyProvider:(id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
{
    TNLAssert(retryPolicyProvider != nil);
    TNLAssert(!_backgroundFlags.inRetryCheck);

    _backgroundFlags.inRetryCheck = YES;

    const BOOL hasCachedCancel = _cachedCancelError != nil;
    const id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    const uint64_t enqueueMachTime = _metrics.enqueueMachTime;
#pragma clang diagnostic pop
    TNLRequestConfiguration *requestConfig = _requestConfiguration;

    // Dispatch to the retry queue to get retry policy info
    tnl_dispatch_barrier_async_autoreleasing(_RetryPolicyProviderQueue(retryPolicyProvider), ^{

        NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), @selector(tnl_shouldRetryRequestOperation:withResponse:));
        [self _updateTag:tag];
        const BOOL retry = [retryPolicyProvider tnl_shouldRetryRequestOperation:self
                                                                   withResponse:attemptResponse];
        [self _clearTag:tag];

        if (retry) {

            NSTimeInterval operationTimeout = requestConfig.operationTimeout;
            BOOL didUpdateOperationTimeout = NO;
            TNLRequestConfiguration *newConfig = [self _retryQueue_pullNewRequestConfigurationFromPolicy:retryPolicyProvider
                                                                                         attemptResponse:attemptResponse
                                                                                        oldConfiguration:requestConfig];
            if (newConfig) {
                TNLLogDebug(@"Retry policy updated config: %@", @{
                                                                  @"operation" : self,
                                                                  @"attemptResponse" : attemptResponse,
                                                                  @"oldConfig" : requestConfig,
                                                                  @"newConfig" : newConfig
                                                                  });
                const NSTimeInterval newTimeout = newConfig.operationTimeout;
                if (newTimeout != operationTimeout) {
                    operationTimeout = newTimeout;
                    didUpdateOperationTimeout = YES;
                }
            }

            const BOOL hasOperationTimeout = operationTimeout >= MIN_TIMER_INTERVAL;
            const NSTimeInterval retryDelay = [self _retryQueue_pullRetryDelayFromPolicy:retryPolicyProvider attemptResponse:attemptResponse];
            const NSTimeInterval elapsedTime = TNLComputeDuration(enqueueMachTime, mach_absolute_time());

            // Only retry if the attempt won't be too far into the future
            if (!hasOperationTimeout || ((elapsedTime + retryDelay) < operationTimeout)) {
                TNLLogDebug(@"Retry will start in %.3f seconds", retryDelay);

                NSTimeInterval newOperationTimeout = -1.0; // negative won't update timeout
                if (didUpdateOperationTimeout && hasOperationTimeout) {
                    newOperationTimeout = operationTimeout - elapsedTime;
                    TNLAssert(newOperationTimeout >= 0.0);
                }
                [self _retryQueue_doRetryWithPolicy:retryPolicyProvider
                                           oldState:oldState
                                    attemptResponse:attemptResponse
                                         retryDelay:retryDelay
                                       eventHandler:eventHandler
                                    hasCachedCancel:hasCachedCancel
                                   newConfiguration:newConfig
                                newOperationTimeout:newOperationTimeout];
                return;
            }

            TNLLogDebug(@"Retry is past timeout, not retrying");
        }

        // won't retry
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            self->_backgroundFlags.inRetryCheck = NO;
            if ([self _network_isStateFinished]) {
                return;
            }

            TNLAssert(attemptResponse != nil);
            [self _network_completeTransitionFromState:oldState
                                               toState:state
                                   withAttemptResponse:attemptResponse];
        });
    });
}

#pragma mark Retry Static Functions

- (NSTimeInterval)_retryQueue_pullRetryDelayFromPolicy:(id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
                                       attemptResponse:(TNLResponse *)attemptResponse TNL_OBJC_DIRECT
{
    // get retry delay from retry policy provider
    const SEL delayCallback = @selector(tnl_delayBeforeRetryForRequestOperation:withResponse:);
    NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), delayCallback);
    [self _updateTag:tag];
    NSTimeInterval retryDelay = 0.0;
    if ([retryPolicyProvider respondsToSelector:delayCallback]) {
        retryDelay = [retryPolicyProvider tnl_delayBeforeRetryForRequestOperation:self
                                                                     withResponse:attemptResponse];
    }
    [self _clearTag:tag];

    if (retryDelay < MIN_TIMER_INTERVAL) {
        retryDelay = MIN_TIMER_INTERVAL;
    }

    return retryDelay;
}

- (nullable TNLRequestConfiguration *)_retryQueue_pullNewRequestConfigurationFromPolicy:(id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
                                                                        attemptResponse:(TNLResponse *)attemptResponse
                                                                       oldConfiguration:(TNLRequestConfiguration *)oldConfig TNL_OBJC_DIRECT
{
    TNLRequestConfiguration *newConfig = nil;

    // get new request config from retry policy provider and update _requestConfiguration_ if necessary
    const SEL newConfigCallback = @selector(tnl_configurationOfRetryForRequestOperation:withResponse:priorConfiguration:);
    if ([retryPolicyProvider respondsToSelector:newConfigCallback]) {
        NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), newConfigCallback);
        [self _updateTag:tag];
        newConfig = [[retryPolicyProvider tnl_configurationOfRetryForRequestOperation:self
                                                                         withResponse:attemptResponse
                                                                   priorConfiguration:oldConfig] copy];
        [self _clearTag:tag];

        if (newConfig && newConfig == oldConfig) {
            newConfig = nil;
        }
    }

    return newConfig;
}

- (void)_retryQueue_doRetryWithPolicy:(id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
                             oldState:(TNLRequestOperationState)oldState
                      attemptResponse:(TNLResponse *)attemptResponse
                           retryDelay:(NSTimeInterval)retryDelay
                         eventHandler:(id<TNLRequestEventHandler>)eventHandler
                      hasCachedCancel:(BOOL)hasCachedCancel
                     newConfiguration:(TNLRequestConfiguration *)newConfig
                  newOperationTimeout:(NSTimeInterval)newOperationTimeout TNL_OBJC_DIRECT
{
    SEL willStartRetryCallback = @selector(tnl_requestOperation:willStartRetryFromResponse:afterDelay:);
    if (!hasCachedCancel) {
        if ([retryPolicyProvider respondsToSelector:willStartRetryCallback]) {
            NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), willStartRetryCallback);
            [self _updateTag:tag];
            [retryPolicyProvider tnl_requestOperation:self
                           willStartRetryFromResponse:attemptResponse
                                           afterDelay:retryDelay];
            [self _clearTag:tag];
        }
    }

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        self->_backgroundFlags.inRetryCheck = NO;
        if ([self _network_hasFailedOrFinished]) {
            return;
        }

        // don't use stale hasCachedCancel var here,
        // check the fresh _cachedCancel ref directly
        if (self->_cachedCancelError != nil) {
            [self _network_fail:self->_cachedCancelError];
            return;
        }

        if (newConfig) {
            // update the config
            self->_requestConfiguration = newConfig;
            // update the operation timeout if it had changed
            if (newOperationTimeout > 0) {
                [self _network_invalidateOperationTimeoutTimer];
                [self _network_startOperationTimeoutTimer:newOperationTimeout];
            }
        }

        self.URLSessionTaskOperation = nil;

        // Transition to "Waiting to Retry", forcibly updating to "Starting" first, if necessary
        TNLRequestOperationState updatedOldState = oldState;
        if (TNLRequestOperationStatePreparingRequest == oldState) {
            [self _network_completeTransitionFromState:oldState
                                               toState:TNLRequestOperationStateStarting
                                   withAttemptResponse:nil];
            updatedOldState = TNLRequestOperationStateStarting;
        }
        [self _network_completeTransitionFromState:updatedOldState
                                           toState:TNLRequestOperationStateWaitingToRetry
                               withAttemptResponse:attemptResponse];

        // Dispatch to the callback queue in case we need to event to the event handler
        SEL eventHandlerWillStartRetryCallback = @selector(tnl_requestOperation:willStartRetryFromResponse:policyProvider:afterDelay:);
        tnl_dispatch_barrier_async_autoreleasing(self->_callbackQueue, ^{
            if ([eventHandler respondsToSelector:eventHandlerWillStartRetryCallback] && ((__bridge void *)eventHandler != (__bridge void *)retryPolicyProvider)) {
                NSString *eventTag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), eventHandlerWillStartRetryCallback);
                [self _updateTag:eventTag];
                [eventHandler tnl_requestOperation:self
                        willStartRetryFromResponse:attemptResponse
                                    policyProvider:retryPolicyProvider
                                        afterDelay:retryDelay];
                [self _clearTag:eventTag];
            }

            // Finish with dispatch to background queue to start retry timer
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                [self _network_startRetryWithDelay:retryDelay
                                       oldResponse:attemptResponse
                               retryPolicyProvider:retryPolicyProvider];
                // end the background task while waiting to retry,
                // we only want the active request to be guarded with a bg task
                [self _network_endBackgroundTask];
            });
        });
    });
}

#pragma mark Retry

- (void)_network_startRetryWithDelay:(NSTimeInterval)retryDelay
                         oldResponse:(TNLResponse *)oldResponse
                 retryPolicyProvider:(nullable id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
{
    // Update the active retry number (effectively invalidating prior retries)
    const uint64_t currentRetryId = atomic_fetch_add(&sNextRetryId, 1);
    _activeRetryId = currentRetryId;

    // The block try the actual retry
    __weak typeof(self) weakSelf = self;
    dispatch_block_t tryRetryBlock = ^{
        [weakSelf _network_tryRetryWithId:currentRetryId
                              oldResponse:oldResponse
                      retryPolicyProvider:retryPolicyProvider];
    };

    // Can we retry without any delay?
    NSArray<NSOperation *> *dependencies = self.dependencies;
    if (dependencies.count == 0 && retryDelay < MIN_TIMER_INTERVAL) {
        // retry without a delay
        tryRetryBlock();
        return;
    }

    // Set up operation to gate the retry on
    NSOperation *retryDependencyOperation = [[TNLSafeOperation alloc] init];
    retryDependencyOperation.completionBlock = ^{
        if (dispatch_queue_get_label(tnl_network_queue()) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)) {
            tryRetryBlock();
        } else {
            dispatch_async(tnl_network_queue(), tryRetryBlock);
        }
    };

    // Set up dependencies
    for (NSOperation *op in dependencies) {
        if (!op.isFinished && !op.isCancelled) {
            [retryDependencyOperation addDependency:op];
        }
    }
    if (retryDelay >= MIN_TIMER_INTERVAL) {
        // the retry delay is concurrent with the other dependencies, so it doesn't need the other
        // dependencies itself and simply be added to our dependency operation
        NSOperation *delayOp = [[TNLTimerOperation alloc] initWithDelay:retryDelay];
        [retryDependencyOperation addDependency:delayOp];
        [TNLNetworkOperationQueue() addOperation:delayOp];
    }

    // Add our dependency operation to wait for our retry to trigger
    [TNLNetworkOperationQueue() addOperation:retryDependencyOperation];
}

- (void)_network_invalidateRetry
{
    _activeRetryId = 0;
}

- (void)_network_tryRetryWithId:(uint64_t)retryId
                    oldResponse:(TNLResponse *)oldResponse
            retryPolicyProvider:(nullable id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
{
    if (retryId == _activeRetryId) {
        TNLLogInformation(@"%@::_network_tryRetry", self);
        [self _network_retryWithOldResponse:oldResponse
                        retryPolicyProvider:retryPolicyProvider];
    }
}

#pragma mark Operation Timeout Timer

- (void)_network_startOperationTimeoutTimer:(NSTimeInterval)timeInterval
{
    if (!_operationTimeoutTimerSource && timeInterval >= MIN_TIMER_INTERVAL) {
        __weak typeof(self) weakSelf = self;
        _operationTimeoutTimerSource = tnl_dispatch_timer_create_and_start(tnl_network_queue(),
                                                                           timeInterval,
                                                                           TIMER_LEEWAY_WITH_FIRE_INTERVAL(timeInterval),
                                                                           NO /*repeats*/,
                                                                           ^{
            [weakSelf _network_operationTimeoutTimerDidFire];
        });
    }
}

- (void)_network_invalidateOperationTimeoutTimer
{
    tnl_dispatch_timer_invalidate(_operationTimeoutTimerSource);
    _operationTimeoutTimerSource = NULL;
}

- (void)_network_operationTimeoutTimerDidFire
{
    if (_operationTimeoutTimerSource) {
        TNLLogInformation(@"%@::_network_operationTimeoutTimerDidFire", self);

        [self _network_invalidateOperationTimeoutTimer];
        [self _network_invalidateAttemptTimeoutTimer];
        [self _network_invalidateRetry];

        if (![self _network_hasFailedOrFinished]) {
            [self _network_fail:TNLErrorCreateWithCode(TNLErrorCodeRequestOperationOperationTimedOut)];
        }
    }
}

#pragma mark Callback Timeout Timer

- (void)_network_startCallbackTimerWithAlreadyElapsedDuration:(NSTimeInterval)alreadyElapsedTime
{
    TNLAssert(!_callbackTimeoutTimerSource);

    if (_backgroundFlags.isCallbackClogDetectionEnabled) {

#if TARGET_OS_IOS || TARGET_OS_TV
        if (!TNLIsExtension()) {

            // Lazily prep our app backgrounding observing
            if (!_backgroundFlags.isObservingApplicationStates) {
                [self _network_startObservingApplicationStates];
            }

            if (_backgroundFlags.applicationIsInBackground) {
                // already in the background or is inactive!  Set our mach times.
                _callbackTimeoutTimerStartMachTime = _callbackTimeoutTimerPausedMachTime = mach_absolute_time();
                return;
            }
        }
#endif // IOS + TV

        __weak typeof(self) weakSelf = self;
        _callbackTimeoutTimerSource = tnl_dispatch_timer_create_and_start(tnl_network_queue(),
                                                                          _cloggedCallbackTimeout - alreadyElapsedTime,
                                                                          TIMER_LEEWAY_WITH_FIRE_INTERVAL(_cloggedCallbackTimeout),
                                                                          NO /*repeats*/,
                                                                          ^{
            [weakSelf _network_callbackTimerFired];
        });
        _callbackTimeoutTimerStartMachTime = mach_absolute_time() - TNLAbsoluteFromTimeInterval(alreadyElapsedTime);
    }
}

- (void)_network_stopCallbackTimer
{
    tnl_dispatch_timer_invalidate(_callbackTimeoutTimerSource);
    _callbackTimeoutTimerSource = NULL;
    _callbackTimeoutTimerPausedMachTime = 0;
}

- (void)_network_startCallbackTimerIfNecessary
{
    if (!_callbackTimeoutTimerSource) {
        [self _network_startCallbackTimerWithAlreadyElapsedDuration:0.0];
    }
}

- (void)_network_callbackTimerFired
{
    if (_callbackTimeoutTimerSource) {
        [self _network_stopCallbackTimer];
        if (![self _network_hasFailedOrFinished]) {
            [self _network_fail:TNLErrorCreateWithCode(TNLErrorCodeRequestOperationCallbackTimedOut)];
        }
    }
}

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)_network_pauseCallbackTimer
{
    if (_callbackTimeoutTimerSource) {
        [self _network_stopCallbackTimer];
        _callbackTimeoutTimerPausedMachTime = mach_absolute_time();
    }
}

- (void)_network_unpauseCallbackTimer
{
    if (_callbackTimeoutTimerPausedMachTime) {
        const NSTimeInterval timeElapsed = TNLComputeDuration(_callbackTimeoutTimerStartMachTime,
                                                              _callbackTimeoutTimerPausedMachTime);
        _callbackTimeoutTimerPausedMachTime = 0;
        [self _network_startCallbackTimerWithAlreadyElapsedDuration:timeElapsed];
    }
}
#endif // IOS + TV

#pragma mark Attempt Timeout Timer

- (void)_network_startAttemptTimeoutTimer:(NSTimeInterval)timeInterval
{
    if (!_attemptTimeoutTimerSource && timeInterval >= MIN_TIMER_INTERVAL) {
        __weak typeof(self) weakSelf = self;
        _attemptTimeoutTimerSource = tnl_dispatch_timer_create_and_start(tnl_network_queue(),
                                                                         timeInterval,
                                                                         TIMER_LEEWAY_WITH_FIRE_INTERVAL(timeInterval),
                                                                         NO /*repeats*/,
                                                                         ^{
            [weakSelf _network_attemptTimeoutTimerDidFire];
        });
    }
}

- (void)_network_invalidateAttemptTimeoutTimer
{
    tnl_dispatch_timer_invalidate(_attemptTimeoutTimerSource);
    _attemptTimeoutTimerSource = NULL;
}

- (void)_network_attemptTimeoutTimerDidFire
{
    if (_attemptTimeoutTimerSource) {
        TNLLogInformation(@"%@::_network_attemptTimeoutTimerDidFire", self);

        [self _network_invalidateAttemptTimeoutTimer];
        [self _network_invalidateRetry];
        // Don't invalidate the operation timeout

        if (![self _network_hasFailedOrFinished]) {
            [self _network_fail:TNLErrorCreateWithCode(TNLErrorCodeRequestOperationAttemptTimedOut)];
        }
    }
}

#pragma mark Background (iOS)

- (void)_noop TNL_OBJC_DIRECT
{
}

- (void)_private_willResignActive:(NSNotification *)note
{
    TNLGlobalConfiguration *config = [TNLGlobalConfiguration sharedInstance];
    TNLBackgroundTaskIdentifier taskID = [config startBackgroundTaskWithName:@"-[TNLRequestOperation private_willResignActive:]"
                                                           expirationHandler:^{
        // capture self
        [self _noop];
    }];
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_willResignActive];
        [config endBackgroundTaskWithIdentifier:taskID];
    });
}

- (void)_private_didBecomeActive:(NSNotification *)note
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_didBecomeActive];
    });
}

- (void)_network_willResignActive
{
#if TARGET_OS_IOS || TARGET_OS_TV
    _backgroundFlags.applicationIsInBackground = 1;
    [self _network_pauseCallbackTimer];
#endif
}

- (void)_network_didBecomeActive
{
#if TARGET_OS_IOS || TARGET_OS_TV
    _backgroundFlags.applicationIsInBackground = 0;
    [self _network_unpauseCallbackTimer];
#endif
}

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)_network_startObservingApplicationStates
{
    TNLAssert(!_backgroundFlags.isObservingApplicationStates);
    TNLAssert(!TNLIsExtension());

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(_private_willResignActive:)
               name:UIApplicationWillResignActiveNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(_private_didBecomeActive:)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];

    if ([TNLGlobalConfiguration sharedInstance].lastApplicationState != UIApplicationStateActive) {
        _backgroundFlags.applicationIsInBackground = 1;
    } else {
        _backgroundFlags.applicationIsInBackground = 0;
    }

    _backgroundFlags.isObservingApplicationStates = 1;
}
#endif // IOS + TV

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)_dealloc_stopObservingApplicationStatesIfNecessary TNL_THREAD_SANITIZER_DISABLED
{
    if (_backgroundFlags.isObservingApplicationStates) {
        TNLAssert(!TNLIsExtension());
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc removeObserver:self
                      name:UIApplicationWillResignActiveNotification
                    object:nil];
        [nc removeObserver:self
                      name:UIApplicationDidBecomeActiveNotification
                    object:nil];
        _backgroundFlags.isObservingApplicationStates = 0;
    }
}
#endif // IOS + TV

- (void)_network_startBackgroundTask
{
#if TARGET_OS_IOS || TARGET_OS_TV
    if (TNLBackgroundTaskInvalid != _backgroundTaskIdentifier) {
        return;
    }

    _backgroundTaskIdentifier = [[TNLGlobalConfiguration sharedInstance] startBackgroundTaskWithName:@"tnl.request.op"
                                                                                   expirationHandler:^{
        dispatch_sync(tnl_network_queue(), ^{
            self->_backgroundTaskIdentifier = TNLBackgroundTaskInvalid;
        });
    }];
#endif // IOS + TV
}

- (void)_network_endBackgroundTask
{
#if TARGET_OS_IOS || TARGET_OS_TV
    if (TNLBackgroundTaskInvalid == _backgroundTaskIdentifier) {
        return;
    }

    [[TNLGlobalConfiguration sharedInstance] endBackgroundTaskWithIdentifier:_backgroundTaskIdentifier];
    _backgroundTaskIdentifier = TNLBackgroundTaskInvalid;
#endif // IOS + TV
}

@end

#pragma mark - TNLRequestOperation (Convenience)

@implementation TNLRequestOperation (Convenience)

+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       configuration:(nullable TNLRequestConfiguration *)config
                            delegate:(nullable id<TNLRequestDelegate>)delegate
{
    return [self operationWithRequest:request
                        responseClass:Nil
                        configuration:config
                             delegate:delegate];
}

+ (instancetype)operationWithURL:(nullable NSURL *)url
                   configuration:(nullable TNLRequestConfiguration *)config
                        delegate:(nullable id<TNLRequestDelegate>)delegate
{
    return [self operationWithRequest:(url) ? [NSURLRequest requestWithURL:url] : nil
                        configuration:config
                             delegate:delegate];
}

+ (instancetype)operationWithURL:(nullable NSURL *)url
                      completion:(nullable TNLRequestDidCompleteBlock)completion
{
    return [self operationWithRequest:(url) ? [NSURLRequest requestWithURL:url] : nil
                           completion:completion];
}

+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                          completion:(nullable TNLRequestDidCompleteBlock)completion
{
    return [self operationWithRequest:request
                        configuration:nil
                           completion:completion];
}

+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       configuration:(nullable TNLRequestConfiguration *)config
                          completion:(nullable TNLRequestDidCompleteBlock)completion
{
    return [self operationWithRequest:request
                        responseClass:Nil
                        configuration:config
                           completion:completion];
}

+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       responseClass:(nullable Class)responseClass
                       configuration:(nullable TNLRequestConfiguration *)config
                          completion:(nullable TNLRequestDidCompleteBlock)completion
{
    TNLSimpleRequestDelegate *delegate = nil;
    if (completion) {
        delegate = [[TNLSimpleRequestDelegate alloc] initWithDidCompleteBlock:completion];
    }

    return [self operationWithRequest:request
                        responseClass:responseClass
                        configuration:config
                             delegate:delegate];
}

@end

@implementation TNLRequestOperation (Tagging)

- (void)_updateTag:(NSString *)tag
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (!self->_mach_callbackTagTime) {
            self->_mach_callbackTagTime = mach_absolute_time();
        }
        [self->_callbackTagStack addObject:tag];
        [self _network_startCallbackTimerIfNecessary];
    });
}

- (void)_clearTag:(NSString *)tag
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self->_callbackTagStack removeObject:tag];
        if (self->_callbackTagStack.count == 0) {
            self->_mach_callbackTagTime = 0;
            [self _network_stopCallbackTimer];
        }
    });
}

@end

#pragma mark - TNLTimerOperation

@implementation TNLTimerOperation
{
    NSTimeInterval _delay;
    volatile atomic_bool _finished;
    volatile atomic_bool _executing;
}

- (instancetype)initWithDelay:(NSTimeInterval)delay
{
    if (self = [self init]) {
        _delay = delay;
    }
    return self;
}

- (instancetype)init
{
    if (self = [super init]) {
        atomic_init(&_finished, false);
        atomic_init(&_executing, false);
    }
    return self;
}

- (void)start
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        atomic_store(&_finished, true);
        [self didChangeValueForKey:@"isFinished"];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&_executing, true);
    [self didChangeValueForKey:@"isExecuting"];
    [self run];
}

- (void)run
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_delay * NSEC_PER_SEC)), tnl_network_queue(), ^{
        [self completeOperation];
    });
}

- (BOOL)isExecuting
{
    return atomic_load(&_executing);
}

- (BOOL)isFinished
{
    return atomic_load(&_finished);
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (void)completeOperation
{
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&_executing, false);
    atomic_store(&_finished, true);
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

#pragma mark - Functions

NSString *TNLRequestOperationStateToString(TNLRequestOperationState state)
{
#define OP_CASE(c) \
case TNLRequestOperationState##c : { return @"" #c ; }

    switch (state) {
            OP_CASE(Idle)

            // Set by TNLRequestOperation
            OP_CASE(PreparingRequest)
            OP_CASE(Starting)

            // Set by TNLURLSessionTaskOperation
            OP_CASE(Running)
            OP_CASE(WaitingToRetry)

            // Set by TNLRequestOperation or TNLURLSessionTaskOperation
            OP_CASE(Cancelled)
            OP_CASE(Failed)
            OP_CASE(Succeeded)
    }

    TNLAssertNever();
    return nil;
#undef OP_CASE
}

NS_ASSUME_NONNULL_END

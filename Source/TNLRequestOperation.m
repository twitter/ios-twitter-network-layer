//
//  TNLRequestOperation.m
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
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

#define SELF_ARG PRIVATE_SELF(TNLRequestOperation)

NS_ASSUME_NONNULL_BEGIN

#define TAG_FROM_METHOD(DELEGATE, PROTOCOL, SEL) [NSString stringWithFormat:@"%@<%@>->%@", NSStringFromClass([DELEGATE class]), NSStringFromProtocol(PROTOCOL), NSStringFromSelector(SEL)]

static NSString * const kRedactedKeyValue = @"<redacted>";

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

@interface TNLRequestOperation ()

// Private Properties
#pragma twitter startignorestylecheck
@property (nonatomic, readonly, nullable) id<TNLRequestDelegate> internalDelegate;
@property (atomic, copy, nullable) NSString *cachedDelegateClassName; // annoyingly the Twitter style checker considers this a delegate, so we'll wrap it in the ignorestylecheck
#pragma twitter endignorestylecheck
@property (atomic, nullable) NSError *terminalErrorOverride;
@property (atomic, readonly) TNLResponseSource responseSource;
@property (nonatomic, readonly) TNLRequestExecutionMode executionMode;
@property (atomic) TNLPriority internalPriority;
@property (atomic, nullable) TNLResponse *internalFinalResponse;

// Private Writability
@property (nonatomic, nullable) TNLRequestOperationQueue *requestOperationQueue;
@property (nonatomic, nullable) id<TNLRequest> hydratedRequest;
@property (nonatomic) float downloadProgress;
@property (nonatomic) float uploadProgress;
@property (atomic, nullable) TNLURLSessionTaskOperation *URLSessionTaskOperation;
@property (atomic, copy, nullable) NSDictionary<NSString *, id<TNLContentDecoder>> *additionalDecoders;
@property (atomic, copy, nullable) NSURLRequest *hydratedURLRequest;

@end

@interface TNLRequestOperation (Network)

// Methods that can only be called from the tnl_network_queue()

#pragma mark NSOperation helpers

static void _network_prepareToConnectThenConnect(SELF_ARG,
                                                 BOOL isRetry);
static void _network_connect(SELF_ARG,
                             BOOL isRetry);
static void _network_startURLSessionTaskOperation(SELF_ARG,
                                                  TNLURLSessionTaskOperation *taskOp,
                                                  BOOL isRetry);
static void _network_fail(SELF_ARG,
                          NSError *error);

#pragma mark NSOperation

static void _network_retry(SELF_ARG,
                           TNLResponse *oldResponse,
                           id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider);
static void _network_prepareToStart(SELF_ARG);
static void _network_start(SELF_ARG,
                           BOOL isRetry);
static void _network_cleanupAfterComplete(SELF_ARG);

#pragma mark Private Methods

static void _network_transitionState(SELF_ARG,
                                     TNLRequestOperationState state,
                                     TNLResponse * __nullable attemptResponse);
static void _network_completeStateTransition(SELF_ARG,
                                             TNLRequestOperationState oldState,
                                             TNLRequestOperationState state,
                                             TNLResponse * __nullable attemptResponse);
static TNLResponse *_network_finalizeResponse(SELF_ARG,
                                              TNLResponseInfo *responseInfo,
                                              NSError * __nullable responseError,
                                              TNLAttemptMetaData * __nullable metadata,
                                              NSURLSessionTaskMetrics * __nullable taskMetrics);
static void _network_applyEncodingMetrics(SELF_ARG,
                                          TNLResponseInfo *responseInfo,
                                          TNLAttemptMetaData * __nullable metadata);
static void _network_updateMetrics(SELF_ARG,
                                   TNLRequestOperationState oldState,
                                   TNLRequestOperationState newState,
                                   TNLResponse * __nullable attemptResponse);
static void _network_didCompleteAttempt(SELF_ARG,
                                        TNLResponse *response,
                                        TNLAttemptCompleteDisposition disposition);
static void _network_complete(SELF_ARG,
                              TNLResponse *response);

#pragma mark Attempt Retry

// Primary "attempt retry" method
static void _network_attemptRetryDuringStateTransition(SELF_ARG,
                                                       TNLRequestOperationState oldState,
                                                       TNLRequestOperationState state,
                                                       TNLResponse * __nullable attemptResponse);

// Internal methods called by primary "attempt retry" method
static BOOL _network_shouldAttemptRetryDuringStateTransition(SELF_ARG,
                                                             TNLRequestOperationState oldState,
                                                             TNLRequestOperationState state,
                                                             TNLResponse * __nullable attemptResponse);
static BOOL _network_shouldForciblyRetryInvalidatedURLSessionRequest(SELF_ARG,
                                                                     TNLResponse *attemptResponse);
static void _network_forciblyRetryInvalidatedURLSessionRequest(SELF_ARG,
                                                               TNLResponse *attemptResponse);
static void _network_retryDuringStateTransition(SELF_ARG,
                                                TNLRequestOperationState oldState,
                                                TNLRequestOperationState state,
                                                TNLResponse *attemptResponse,
                                                id<TNLRequestRetryPolicyProvider> retryPolicyProvider);

#pragma mark Retry Timer

static void _network_startRetryTimer(SELF_ARG,
                                     NSTimeInterval retryInterval,
                                     TNLResponse *oldResponse,
                                     id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider);
static void _network_invalidateRetryTimer(SELF_ARG);
static void _network_retryTimerDidFire(SELF_ARG,
                                       TNLResponse *oldResponse,
                                       id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider);

#pragma mark Operation Timeout Timer

static void _network_startOperationTimeoutTimer(SELF_ARG,
                                                NSTimeInterval timeInterval);
static void _network_invalidateOperationTimeoutTimer(SELF_ARG);
static void _network_operationTimeoutTimerDidFire(SELF_ARG);

#pragma mark Callback Timeout Timer

static void _network_startCallbackTimer(SELF_ARG,
                                        NSTimeInterval alreadyElapsedTime);
static void _network_startCallbackTimerIfNecessary(SELF_ARG);
static void _network_stopCallbackTimer(SELF_ARG);
static void _network_callbackTimerFired(SELF_ARG);
#if TARGET_OS_IOS || TARGET_OS_TV
static void _network_pauseCallbackTimer(SELF_ARG);
static void _network_unpauseCallbackTimer(SELF_ARG);
#endif

#pragma mark Attempt Timeout Timer

static void _network_startAttemptTimeoutTimer(SELF_ARG,
                                              NSTimeInterval timeInterval);
static void _network_invalidateAttemptTimeoutTimer(SELF_ARG);
static void _network_attemptTimeoutTimerDidFire(SELF_ARG);

#pragma mark Application States (iOS only)

#if TARGET_OS_IOS || TARGET_OS_TV
static void _network_startObservingApplicationStates(SELF_ARG);
static void _dealloc_stopObservingApplicationStatesIfNecessary(SELF_ARG);
#endif
- (void)_private_willResignActive:(NSNotification *)note;
- (void)_private_didBecomeActive:(NSNotification *)note;
static void _network_willResignActive(SELF_ARG);
static void _network_didBecomeActive(SELF_ARG);

#pragma mark Background (iOS only)

static void _network_startBackgroundTask(SELF_ARG);
static void _network_endBackgroundTask(SELF_ARG);

#pragma mark State

static BOOL _network_getIsStateActive(SELF_ARG);
static BOOL _network_getIsStateFinished(SELF_ARG);
static BOOL _network_getIsStateCancelled(SELF_ARG);
static BOOL _network_getHasFailed(SELF_ARG);
static BOOL _network_getHasFailedOrFinished(SELF_ARG);
static BOOL _network_getIsPreparing(SELF_ARG);

#pragma mark Preparation Methods

typedef void (^tnl_request_preparation_block_t)(void);

static void _network_validateOriginalRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_hydrateRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_validateHydratedRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_convertHydratedRequestToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_validateConfiguration(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_applyGlobalHeadersToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_applyAcceptEncodingsToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_applyContentEncodingToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_sanitizeHostForScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_authorizeScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);
static void _network_cementScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock);

static void _network_prepareRequestStep(SELF_ARG,
                                        size_t preparationStepIndex,
                                        BOOL isRetry);

@end

typedef void (*tnl_request_preparation_function_ptr)(SELF_ARG, tnl_request_preparation_block_t block);
static const tnl_request_preparation_function_ptr _Nonnull sPreparationFunctions[] = {
    _network_validateOriginalRequest,
    _network_hydrateRequest,
    _network_validateHydratedRequest,
    _network_convertHydratedRequestToScratchURLRequest,
    _network_validateConfiguration,
    _network_applyGlobalHeadersToScratchURLRequest,
    _network_applyAcceptEncodingsToScratchURLRequest,
    _network_applyContentEncodingToScratchURLRequest,
    _network_sanitizeHostForScratchURLRequest,
    _network_authorizeScratchURLRequest,
    _network_cementScratchURLRequest,
};
static const size_t kPreparationFunctionsCount = (sizeof(sPreparationFunctions) / sizeof(sPreparationFunctions[0]));

@interface TNLRequestOperation (Tagging)

static void _updateTag(SELF_ARG,
                       NSString *tag);
static void _clearTag(SELF_ARG,
                      NSString *tag);

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
    dispatch_source_t _retryDelayTimerSource;
    dispatch_source_t _operationTimeoutTimerSource;
    dispatch_source_t _attemptTimeoutTimerSource;
    dispatch_source_t _callbackTimeoutTimerSource;
    uint64_t _callbackTimeoutTimerStartMachTime;
    uint64_t _callbackTimeoutTimerPausedMachTime;

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
    tnl_dispatch_timer_invalidate(_retryDelayTimerSource);
    tnl_dispatch_timer_invalidate(_operationTimeoutTimerSource);
    tnl_dispatch_timer_invalidate(_attemptTimeoutTimerSource);
    tnl_dispatch_timer_invalidate(_callbackTimeoutTimerSource);

    TNLBackgroundTaskIdentifier backgroundTaskIdentifier = self.dealloc_backgroundTaskIdentifier;
    if (TNLBackgroundTaskInvalid != backgroundTaskIdentifier) {
        [[TNLGlobalConfiguration sharedInstance] endBackgroundTaskWithIdentifier:backgroundTaskIdentifier];
    }

#if TARGET_OS_IOS || TARGET_OS_TV
    _dealloc_stopObservingApplicationStatesIfNecessary(self);
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
    if (!_network_getHasFailedOrFinished(self) && self.URLSessionTaskOperation == taskOp) {

        // Invalidate timeout timer if configured to do so
        if (TNL_BITMASK_INTERSECTS_FLAGS(_requestConfiguration.connectivityOptions, TNLRequestConnectivityOptionInvalidateAttemptTimeoutWhenWaitForConnectivityTriggered)) {
            _network_invalidateAttemptTimeoutTimer(self);
        }

        // Send event
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperartionIsWaitingForConnectivity:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperartionIsWaitingForConnectivity:self];
                    _clearTag(self, tag);
                }
            });
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                  didReceiveURLResponse:(NSURLResponse *)URLResponse
{
    TNLAssertIsNetworkQueue();
    if (!_network_getHasFailedOrFinished(self) && self.URLSessionTaskOperation == taskOp) {
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didReceiveURLResponse:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperation:self
                                 didReceiveURLResponse:URLResponse];
                    _clearTag(self, tag);
                }
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
    _network_willPerformRedirect(self,
                                 taskOp,
                                 fromRequest,
                                 response,
                                 toRequest,
                                 _requestConfiguration.redirectPolicy,
                                 completion);
}

static void _network_willPerformRedirect(SELF_ARG,
                                         TNLURLSessionTaskOperation *taskOp,
                                         NSURLRequest *fromRequest,
                                         NSHTTPURLResponse *response,
                                         NSURLRequest *providedToRequest,
                                         TNLRequestRedirectPolicy redirectPolicy,
                                         TNLRequestRedirectCompletionBlock completion)
{
    if (!self) {
        return;
    }

    TNLAssertIsNetworkQueue();
    if (!_network_getHasFailedOrFinished(self) && self.URLSessionTaskOperation == taskOp) {
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
                    dispatch_barrier_async(self->_callbackQueue, ^{
                        @autoreleasepool {
                            NSString *tag = TAG_FROM_METHOD(redirecter, @protocol(TNLRequestRedirecter), callback);
                            _updateTag(self, tag);
                            [redirecter tnl_requestOperation:self
                                     willRedirectFromRequest:fromRequest
                                                withResponse:response
                                                   toRequest:toRequest
                                                  completion:^(id<TNLRequest> finalToRequest) {
                                _clearTag(self, tag);
                                // all `TNLURLSessionTaskOperationDelegate` completion blocks must be called from tnl_network_queue
                                tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                                    completion(finalToRequest);
                                });
                            }];
                        }
                    });
                } else {
                    // No callback to call, revert to Default behavior
                    TNLLogWarning(@"Use callback specified in redirect policy but %@ not implemented in delegate (%@)", NSStringFromProtocol(@protocol(TNLRequestRedirecter)), redirecter);
                    _network_willPerformRedirect(self,
                                                 taskOp,
                                                 fromRequest,
                                                 response,
                                                 toRequest,
                                                 TNLRequestRedirectPolicyDefault,
                                                 completion);
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
    if (!_network_getHasFailedOrFinished(self) && self.URLSessionTaskOperation == taskOp) {

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
        _network_didCompleteAttempt(self,
                                    placeholderResponse,
                                    TNLAttemptCompleteDispositionRedirecting);
        [self.requestOperationQueue operation:self
                   didStartAttemptWithMetrics:_metrics.attemptMetrics.lastObject];

        // Event the redirect
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didRedirectFromURLRequest:toURLRequest:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperation:self
                             didRedirectFromURLRequest:fromRequest
                                          toURLRequest:toRequest];
                    _clearTag(self, tag);
                }
            });
        }
   }
}

static void _network_notifyHostSanitized(SELF_ARG,
                                         NSString *oldHost,
                                         NSString *newHost)
{
    if (!self) {
        return;
    }

    TNLAssertIsNetworkQueue();
    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:didSanitizeFromHost:toHost:);
    if ([eventHandler respondsToSelector:callback]) {
        dispatch_barrier_async(self->_callbackQueue, ^{
            @autoreleasepool {
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                _updateTag(self, tag);
                [eventHandler tnl_requestOperation:self
                               didSanitizeFromHost:oldHost
                                            toHost:newHost];
                _clearTag(self, tag);
            }
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
                    _network_notifyHostSanitized(self, host, newHost);
                } else {
                    mRequest = nil;
                }

                if (error) {
                    _network_fail(self, error);
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
    if (!_network_getHasFailedOrFinished(self)) {
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didUpdateUploadProgress:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperation:self
                               didUpdateUploadProgress:progress];
                    _clearTag(self, tag);
                }
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
    if (!_network_getHasFailedOrFinished(self)) {
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didUpdateDownloadProgress:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperation:self
                             didUpdateDownloadProgress:progress];
                    _clearTag(self, tag);
                }
            });
        }
    }
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                     appendReceivedData:(NSData *)data
{
    TNLAssertIsNetworkQueue();
    if (!_network_getHasFailedOrFinished(self) && self.URLSessionTaskOperation == taskOp) {
        switch (_requestConfiguration.responseDataConsumptionMode) {
            case TNLResponseDataConsumptionModeChunkToDelegateCallback: {
                id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
                SEL callback = @selector(tnl_requestOperation:didReceiveData:);
                if ([eventHandler respondsToSelector:callback]) {
                    dispatch_barrier_async(self->_callbackQueue, ^{
                        @autoreleasepool {
                            NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                            _updateTag(self, tag);
                            [eventHandler tnl_requestOperation:self
                                                didReceiveData:data];
                            _clearTag(self, tag);
                        }
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
    if (!_network_getHasFailedOrFinished(self) && self.URLSessionTaskOperation == taskOp) {
        TNLAssert((self.executionMode == TNLRequestExecutionModeBackground) == isBackgroundRequest);
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didStartRequestWithURLSessionTaskIdentifier:URLSessionConfigurationIdentifier:URLSessionSharedContainerIdentifier:isBackgroundRequest:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperation:self
                                  didStartRequestWithURLSessionTaskIdentifier:taskId
                                  URLSessionConfigurationIdentifier:configIdentifier
                                  URLSessionSharedContainerIdentifier:sharedContainerIdentifier
                                  isBackgroundRequest:isBackgroundRequest];
                    _clearTag(self, tag);
                }
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
    if (self.URLSessionTaskOperation != taskOp || _network_getHasFailedOrFinished(self)) {
        completion(nil);
        return;
    }

    TNLResponse *response = _network_finalizeResponse(self,
                                                      responseInfo,
                                                      responseError,
                                                      metadata,
                                                      taskMetrics);
    completion(response);
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                   didTransitionToState:(TNLRequestOperationState)state
                           withResponse:(nullable TNLResponse *)response
{
    TNLAssertIsNetworkQueue();
    TNLAssert(state != TNLRequestOperationStateIdle);
    if (self.URLSessionTaskOperation != taskOp || _network_getHasFailedOrFinished(self)) {
        return;
    }

    _network_transitionState(self, state, response);
}

- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
         didStartSessionTaskWithRequest:(NSURLRequest *)request
{
    TNLAssertIsNetworkQueue();
    if (self.URLSessionTaskOperation != taskOp || _network_getHasFailedOrFinished(self)) {
        return;
    }

    TNLRequestOperationState state = atomic_load(&_state);
    if (TNLRequestOperationStateStarting == state) {
        [_metrics updateCurrentRequest:request];
    }
}

#pragma mark Wait

- (void)waitUntilFinished
{
    [super waitUntilFinished];
}

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
        if (self->_cachedCancelError || _network_getHasFailedOrFinished(self)) {
            return;
        }

        NSError *error = TNLErrorFromCancelSource(source, optionalUnderlyingError);
        self->_cachedCancelError = error;
        _network_fail(self, error);
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
    return _network_getIsStateFinished(self) && atomic_load(&_didCompleteFinishedCallback);
}

- (BOOL)isCancelled
{
    return _network_getIsStateCancelled(self);
}

- (BOOL)isExecuting
{
    if (_network_getIsStateActive(self)) {
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

        if (_network_getHasFailedOrFinished(self)) {
            // might have been pre-emptively cancelled or failed
            return;
        }

        _network_prepareToStart(self);

        self->_backgroundFlags.didStart = YES;
        [self->_requestOperationQueue operationDidStart:self];
        _network_startOperationTimeoutTimer(self, self->_requestConfiguration.operationTimeout);
        TNLAssert(self->_metrics.attemptCount == 0);

        if (self->_cachedCancelError) {
            _network_fail(self, self->_cachedCancelError);
        } else {
            _network_start(self, NO /*isRetry*/);
        }
    });
}

@end

#pragma mark - TNLRequestOperation (Network)

@implementation TNLRequestOperation (Network)

#pragma mark Operation State Accessors

static BOOL _network_getIsStateFinished(SELF_ARG)
{
    if (!self) {
        return NO;
    }

    return TNLRequestOperationStateIsFinal(atomic_load(&self->_state));
}

static BOOL _network_getIsStateCancelled(SELF_ARG)
{
    if (!self) {
        return NO;
    }

    return TNLRequestOperationStateCancelled == atomic_load(&self->_state);
}

static BOOL _network_getIsStateActive(SELF_ARG)
{
    if (!self) {
        return NO;
    }

    return TNLRequestOperationStateIsActive(atomic_load(&self->_state));
}

static BOOL _network_getHasFailed(SELF_ARG)
{
    if (!self) {
        return NO;
    }

    return self.terminalErrorOverride != nil;
}

static BOOL _network_getHasFailedOrFinished(SELF_ARG)
{
    if (!self) {
        return NO;
    }

    return _network_getHasFailed(self) || _network_getIsStateFinished(self);
}

static BOOL _network_getIsPreparing(SELF_ARG)
{
    if (!self) {
        return NO;
    }

    return self.state == TNLRequestOperationStatePreparingRequest && !_network_getHasFailedOrFinished(self);
}

#pragma mark Preparation Methods

static void _network_prepareRequestStep(SELF_ARG,
                                        size_t preparationStepIndex,
                                        BOOL isRetry)
{
    if (!self) {
        return;
    }

    if (!_network_getIsPreparing(self)) {
        return;
    }

    if (preparationStepIndex >= kPreparationFunctionsCount) {
        _network_connect(self, isRetry);
        return;
    }

    tnl_request_preparation_function_ptr prepareStep = sPreparationFunctions[preparationStepIndex];
    prepareStep(self, ^{
        _network_prepareRequestStep(self, preparationStepIndex+1, isRetry);
    });
}

static void _network_validateOriginalRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

    id<TNLRequest> originalRequest = self.originalRequest;
    NSError *error = nil;
    if (!originalRequest) {
        error = TNLErrorCreateWithCode(TNLErrorCodeRequestOperationRequestNotProvided);
    }

    if (error) {
        _network_fail(self, error);
    } else {
        nextBlock();
    }
}

static void _network_hydrateRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

    id<TNLRequestHydrater> hydrater = self.internalDelegate;
    id<TNLRequest> originalRequest = self.originalRequest;
    SEL callback = @selector(tnl_requestOperation:hydrateRequest:completion:);
    dispatch_barrier_async(self->_callbackQueue, ^{
        @autoreleasepool {
            if ([hydrater respondsToSelector:callback]) {
                NSString *tag = TAG_FROM_METHOD(hydrater, @protocol(TNLRequestHydrater), callback);
                _updateTag(self, tag);
                [hydrater tnl_requestOperation:self
                                hydrateRequest:originalRequest
                                    completion:^(id<TNLRequest> hydratedRequest, NSError *error) {
                    _clearTag(self, tag);

                    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                        if (!_network_getIsPreparing(self)) {
                            return;
                        }

                        if (error) {
                            _network_fail(self, TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationFailedToHydrateRequest, error));
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
        }
    });
}

static void _network_validateHydratedRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

    id<TNLRequest> hydratedRequest = self.hydratedRequest;
    NSError *underlyingError;

    // Validate the request itself
    const BOOL isValid = [TNLRequest validateRequest:hydratedRequest
                                againstConfiguration:self->_requestConfiguration
                                               error:&underlyingError];
    if (!isValid) {
        _network_fail(self, TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationInvalidHydratedRequest, underlyingError));
        return;
    }

    nextBlock();
}

static void _network_convertHydratedRequestToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

    NSError *error = nil;
    id<TNLRequest> request = self.hydratedRequest;
    NSMutableURLRequest *mURLRequest = [TNLRequest mutableURLRequestForRequest:request
                                                                 configuration:self.requestConfiguration
                                                                         error:&error];
    if (!mURLRequest) {
        _network_fail(self, error);
        return;
    }

    self->_scratchURLRequest = mURLRequest;
    self->_scratchURLRequestEncodeLatency = 0;
    self->_scratchURLRequestOriginalBodyLength = 0;
    self->_scratchURLRequestEncodedBodyLength = 0;
    nextBlock();
}

static void _network_validateConfiguration(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

    TNLRequestConfiguration *config = self->_requestConfiguration;

    if (config.attemptTimeout - config.idleTimeout < -0.05) {
        TNLLogWarning(@"Attempt Timeout (%.2f) should not be shorter than the Idle Timeout (%.2f)!", config.attemptTimeout, config.idleTimeout);
    }

    if (config.operationTimeout - config.attemptTimeout < -0.05) {
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

static void _network_applyGlobalHeadersToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

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
        for (NSString *key in defaultHeaders) {
            [self->_scratchURLRequest setValue:defaultHeaders[key] forHTTPHeaderField:key];
        }

        // 2) specified headers
        for (NSString *key in existingHeaders) {
            [self->_scratchURLRequest setValue:existingHeaders[key] forHTTPHeaderField:key];
        }

        // 3) override headers
        for (NSString *key in overrideHeaders) {
            [self->_scratchURLRequest setValue:overrideHeaders[key] forHTTPHeaderField:key];
        }
    }

    nextBlock();
}

static void _network_applyAcceptEncodingsToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));
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

static void _network_applyContentEncodingToScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

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
        _network_fail(self, TNLErrorCreateWithCode(TNLErrorCodeRequestOperationRequestContentEncodingTypeMissMatch));
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
                _network_fail(self, TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationRequestContentEncodingFailed, encoderError));
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

static void _network_sanitizeHostForScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

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
                    _network_notifyHostSanitized(self, host, newHost);
                }

                if (error) {
                    _network_fail(self, error);
                } else {
                    nextBlock();
                }
            });
        }];
    } else {
        nextBlock();
    }
}

static void _network_authorizeScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

    id<TNLRequestAuthorizer> authorizer = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:authorizeURLRequest:completion:);

    if (!authorizer || ![authorizer respondsToSelector:callback]) {
        nextBlock();
        return;
    }

    dispatch_barrier_async(self->_callbackQueue, ^{
        @autoreleasepool {
            NSString *tag = TAG_FROM_METHOD(authorizer, @protocol(TNLRequestAuthorizer), callback);
            _updateTag(self, tag);
            [authorizer tnl_requestOperation:self
                         authorizeURLRequest:[self->_scratchURLRequest copy]
                                  completion:^(NSString *authHeader, NSError *error) {
                _clearTag(self, tag);

                tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                    if (!_network_getIsPreparing(self)) {
                        return;
                    }

                    if (error) {
                        _network_fail(self, TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationFailedToAuthorizeRequest, error));
                        return;
                    }

                    if (authHeader) {
                        [self->_scratchURLRequest setValue:(authHeader.length > 0) ? authHeader : nil
                                        forHTTPHeaderField:@"Authorization"];
                    }
                    nextBlock();
                });
            }];
        }
    });
}

static void _network_cementScratchURLRequest(SELF_ARG, tnl_request_preparation_block_t nextBlock)
{
    if (!self) {
        return;
    }

    TNLAssert(nextBlock != nil);
    TNLAssert(_network_getIsPreparing(self));

    self.hydratedURLRequest = self->_scratchURLRequest;
    self->_scratchURLRequest = nil;

    nextBlock();
}

#pragma mark NSOperation helpers

static void _network_prepareToConnectThenConnect(SELF_ARG,
                                                 BOOL isRetry)
{
    if (!self) {
        return;
    }

    _network_prepareRequestStep(self, 0 /*preparationStepIndex*/, isRetry);
}

static void _network_connect(SELF_ARG,
                             BOOL isRetry)
{
    if (!self) {
        return;
    }

    TNLAssert(_network_getIsPreparing(self));

    TNLAssertMessage(self.URLSessionTaskOperation == nil, @"Already have a TNLURLSessionTaskOperation? state = %@", TNLRequestOperationStateToString(self.state));
    _network_transitionState(self,
                             TNLRequestOperationStateStarting,
                             nil /*attemptResponse*/);

    [self.requestOperationQueue findURLSessionTaskOperationForRequestOperation:self
                                                                      complete:^(TNLURLSessionTaskOperation *taskOp) {
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            _network_startURLSessionTaskOperation(self, taskOp, isRetry);
        });
    }];
}

static void _network_startURLSessionTaskOperation(SELF_ARG,
                                                  TNLURLSessionTaskOperation *taskOp,
                                                  BOOL isRetry)
{
    if (!self) {
        return;
    }

    if (_network_getHasFailedOrFinished(self)) {
        return;
    }

    self.URLSessionTaskOperation = taskOp;

    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:readyToEnqueueUnderlyingNetworkingOperation:enqueueBlock:);
    if (![eventHandler respondsToSelector:callback]) {
        [taskOp enqueueToOperationQueueIfNeeded:self.requestOperationQueue];
        return;
    }

    dispatch_barrier_async(self->_callbackQueue, ^{
        @autoreleasepool {
            NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
            _updateTag(self, tag);
            [eventHandler tnl_requestOperation:self
                          readyToEnqueueUnderlyingNetworkingOperation:isRetry
                          enqueueBlock:^(NSArray<NSOperation *> *dependencies) {
                _clearTag(self, tag);
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
        }
    });
}

static void _network_fail(SELF_ARG,
                          NSError *error)
{
    _network_prepareToStart(self); // in case we fail before we start

    if (_network_getHasFailed(self)) {
        return;
    }

    if (!self->_backgroundFlags.didStart) {
        return;
    }

    if (_network_getIsStateFinished(self)) {
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
        metadata = [URLSessionTaskOperation network_metaData];
        taskMetrics = [URLSessionTaskOperation network_taskMetrics];
    } else {
        metadata = (TNLAttemptMetaData * __nonnull)nil;
        taskMetrics = nil;
    }

    TNLResponse *response = _network_finalizeResponse(self,
                                                      info,
                                                      error,
                                                      metadata,
                                                      taskMetrics);

    if (_network_getIsStateFinished(self)) {
        TNLAssertNever();
        return;
    }

    _network_transitionState(self,
                             (isCancel) ? TNLRequestOperationStateCancelled : TNLRequestOperationStateFailed,
                             response);

    // discard the task operation at the end so all internal states can be updated first before disassociating with the associated task operation
    self.URLSessionTaskOperation = nil;
}

#pragma mark NSOperation

static void _network_retry(SELF_ARG,
                           TNLResponse *oldResponse,
                           id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider)
{
    if (!self) {
        return;
    }

    if (_network_getHasFailedOrFinished(self)) {
        return;
    }

    TNLAssertMessage(TNLRequestOperationStateWaitingToRetry == atomic_load(&self->_state), @"Actual state is %@", TNLRequestOperationStateToString(atomic_load(&self->_state)));
    self.downloadProgress = 0.0;
    self.uploadProgress = 0.0;
    _network_start(self, YES /*isRetry*/);
    if (!self->_backgroundFlags.silentStart) {
        SEL callback = @selector(tnl_requestOperation:didStartRetryFromResponse:);
        if ([retryPolicyProvider respondsToSelector:callback]) {
            dispatch_barrier_async(_RetryPolicyProviderQueue(retryPolicyProvider), ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), callback);
                    _updateTag(self, tag);
                    [retryPolicyProvider tnl_requestOperation:self
                                    didStartRetryFromResponse:oldResponse];
                    _clearTag(self, tag);
                }
            });
        }
        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        callback = @selector(tnl_requestOperation:didStartRetryFromResponse:policyProvider:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(self->_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperation:self
                             didStartRetryFromResponse:oldResponse
                                        policyProvider:retryPolicyProvider];
                    _clearTag(self, tag);
                }
            });
        }
    }
}

static void _network_prepareToStart(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (!self->_backgroundFlags.didStart) {
        if (!self->_backgroundFlags.didPrep) {
            id<TNLRequestDelegate> delegate = self.internalDelegate;

            // Get the callback queue

            self->_callbackQueue = [delegate respondsToSelector:@selector(tnl_delegateQueueForRequestOperation:)] ? [delegate tnl_delegateQueueForRequestOperation:self] :                                 nil;
            if (!self->_callbackQueue) {
                self->_callbackQueue = _RequestOperationDefaultCallbackQueue();
            }

            // Get the completion queue

            self->_completionQueue = [delegate respondsToSelector:@selector(tnl_completionQueueForRequestOperation:)] ? [delegate tnl_completionQueueForRequestOperation:self] : nil;
            if (!self->_completionQueue) {
                self->_completionQueue = dispatch_get_main_queue();
            }

            self->_backgroundFlags.didPrep = YES;
        }
    }
}

static void _network_start(SELF_ARG,
                           BOOL isRetry)
{
    if (!self) {
        return;
    }

    if (_network_getHasFailedOrFinished(self)) {
        // might have been pre-emptively cancelled or failed
        return;
    }

    // Start a background task to keep things running even in the background
    if (TNLRequestExecutionModeInAppBackgroundTask == self->_requestConfiguration.executionMode) {
        _network_startBackgroundTask(self); // noop in macOS
    }

    _network_transitionState(self,
                             TNLRequestOperationStatePreparingRequest,
                             nil /*attemptResponse*/);
    _network_startAttemptTimeoutTimer(self, self->_requestConfiguration.attemptTimeout);

    // add to queue in case there are existing executions backed up
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        _network_prepareToConnectThenConnect(self, isRetry);
    });
}

static void _network_cleanupAfterComplete(SELF_ARG)
{
    if (!self) {
        return;
    }

    _network_invalidateRetryTimer(self);
    _network_invalidateOperationTimeoutTimer(self);
}

#pragma mark Private Methods

static void _network_transitionState(SELF_ARG,
                                     TNLRequestOperationState state,
                                     TNLResponse * __nullable attemptResponse)
{
    if (!self) {
        return;
    }

    if (_network_getIsStateFinished(self)) {
        return;
    }

    const TNLRequestOperationState oldState = atomic_load(&self->_state);
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
            _network_invalidateAttemptTimeoutTimer(self);
        }

        // either start the retry or complete the state transition
        _network_attemptRetryDuringStateTransition(self,
                                                   oldState,
                                                   state,
                                                   attemptResponse);
    }
}

static void _network_completeStateTransition(SELF_ARG,
                                             TNLRequestOperationState oldState,
                                             TNLRequestOperationState state,
                                             TNLResponse * __nullable attemptResponse)
{
    if (!self) {
        return;
    }

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
        TNLAssert(self->_backgroundFlags.didStart);
        TNLAssert(attemptResponse != nil);
    } else if (TNLRequestOperationStateIdle == oldState) {
        executingDidChange = YES;
    }

    // Metrics

    _network_updateMetrics(self,
                           oldState,
                           state,
                           attemptResponse);
    if (attemptResponse) {
        TNLAttemptCompleteDisposition disposition = TNLAttemptCompleteDispositionCompleting;
        if (TNLRequestOperationStateWaitingToRetry == state) {
            disposition = TNLAttemptCompleteDispositionRetrying;
        }
        _network_didCompleteAttempt(self,
                                    attemptResponse,
                                    disposition);
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
    TNLLog(level, @"%@%@: %@ -> %@\n%@", self, self.URLSessionTaskOperation, TNLRequestOperationStateToString(oldState), TNLRequestOperationStateToString(state), _createLogContextString(self, state, attemptResponse));

    // Delegate callback

    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:didTransitionFromState:toState:);
    if ([eventHandler respondsToSelector:callback]) {
        dispatch_barrier_async(self->_callbackQueue, ^{
            @autoreleasepool {
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                _updateTag(self, tag);
                [eventHandler tnl_requestOperation:self
                            didTransitionFromState:oldState
                                           toState:state];
                _clearTag(self, tag);
            }
        });
    }

    // Completion

    if (finishedDidChange) {
        // have aggressive assert here, whether TNL asserts are enabled or not
        __TNLAssert(attemptResponse != nil);
#if NS_BLOCK_ASSERTIONS
        assert(attemptResponse != nil);
#else
        NSCAssert(attemptResponse != nil, @"assertion failed: cannot finish a %@ with a nil TNLResponse!", NSStringFromClass([self class]));
#endif

        [self.requestOperationQueue operation:self
                      didCompleteWithResponse:attemptResponse];
        _network_complete(self, attemptResponse);
    }
}

static void _network_updateMetrics(SELF_ARG,
                                   TNLRequestOperationState oldState,
                                   TNLRequestOperationState newState,
                                   TNLResponse * __nullable attemptResponse)
{
    if (!self) {
        return;
    }

    NSDate *dateNow = [NSDate date];
    const uint64_t machTime = mach_absolute_time();
    if (TNLRequestOperationStateStarting == newState) {
        if (!self->_backgroundFlags.silentStart) {
            // get the hydrated URL request we will be passing to the NSURLSessionTask in the TNLURLSessionTaskOperation
            // ... NOT the currentURLRequest since that won't have been applied yet
            NSURLRequest *request = self.hydratedURLRequest;
            if (!request) {
                // we could be going through a transition to an early failure state during/before hydration,
                // so we'll use some fallbacks to find the best matching request for populating the metrics.

                // try the incomplete scratch request
                request = [self->_scratchURLRequest copy];
                if (!request) {
                    // no scratch request, try the hydrated request
                    request = [TNLRequest URLRequestForRequest:self.hydratedRequest error:NULL];
                    if (!request) {
                        // no hydrated request either, try just the original request
                        request = [TNLRequest URLRequestForRequest:self.originalRequest error:NULL];
                    }
                }
            }
            TNLAssertMessage(request != nil, @"must have a request by time Starting state happens");
            [self willChangeValueForKey:@"attemptCount"];
            if (self->_metrics.attemptCount == 0) {
                [self->_metrics addInitialStartWithDate:dateNow
                                               machTime:machTime
                                                request:request];
                [self.requestOperationQueue operation:self
                           didStartAttemptWithMetrics:self->_metrics.attemptMetrics.lastObject];
            } else {
                // TODO:[nobrien] - if we break apart redirect attempts to own in TNL instead of the NSURLSessionTask,
                // this will need key off what is causing the state to move to Starting (Retry vs Redirect for example)
                [self willChangeValueForKey:@"retryCount"];
                [self->_metrics addRetryStartWithDate:dateNow
                                             machTime:machTime
                                              request:request];
                [self.requestOperationQueue operation:self
                           didStartAttemptWithMetrics:self->_metrics.attemptMetrics.lastObject];
                [self didChangeValueForKey:@"retryCount"];
            }
            [self didChangeValueForKey:@"attemptCount"];
        } else {
            TNLAssert(self->_metrics.attemptCount > 0);
        }
    } else if (TNLRequestOperationStateWaitingToRetry == newState || TNLRequestOperationStateIsFinal(newState)) {
        // We'll have 2 copies of metrics to deal with here
        // 1) is our running metrics which can keep getting extended
        // 2) is our TNLResponse for this attempt
        // Update both copies
        NSHTTPURLResponse *response = self.currentURLResponse;
        NSError *error = self.error ?: attemptResponse.operationError;
        [self->_metrics addEndDate:dateNow
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
                [self->_metrics setCompleteDate:attemptMetrics.completeDate
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                                       machTime:attemptMetrics.completeMachTime];
#pragma clang diagnostic pop
            } else {
                [self->_metrics setCompleteDate:dateNow machTime:machTime];
                [attemptMetrics setCompleteDate:dateNow machTime:machTime];
            }
        }
    }
}

static void _network_didCompleteAttempt(SELF_ARG,
                                        TNLResponse *response,
                                        TNLAttemptCompleteDisposition disposition)
{
    if (!self) {
        return;
    }

    if (response) {
        [self.requestOperationQueue operation:self
                           didCompleteAttempt:response
                                  disposition:disposition];

        id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
        SEL callback = @selector(tnl_requestOperation:didCompleteAttemptWithResponse:disposition:);
        if ([eventHandler respondsToSelector:callback]) {
            dispatch_barrier_async(self->_callbackQueue, ^{
                @autoreleasepool {
                    NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                    _updateTag(self, tag);
                    [eventHandler tnl_requestOperation:self
                        didCompleteAttemptWithResponse:response
                                           disposition:disposition];
                    _clearTag(self, tag);
                }
            });
        }
    }
}

static void _network_complete(SELF_ARG,
                              TNLResponse *response)
{
    if (!self) {
        return;
    }

    _network_prepareToStart(self); // ensure we have variables in case we finished before we started
    _network_cleanupAfterComplete(self);
    [self.requestOperationQueue clearQueuedRequestOperation:self];

    TNLAssert(nil != response);
    TNLAssert(self->_uploadProgress <= 1.0f);
    TNLAssert(self->_downloadProgress <= 1.0f);
    self.internalFinalResponse = response;

    id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
    SEL callback = @selector(tnl_requestOperation:didCompleteWithResponse:);
    const BOOL hasCompletionCallback = [eventHandler respondsToSelector:callback];
    dispatch_block_t block = ^{
        @autoreleasepool {
            if (hasCompletionCallback) {
                NSString *tag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), callback);
                _updateTag(self, tag);
                [eventHandler tnl_requestOperation:self
                           didCompleteWithResponse:response];
                _clearTag(self, tag);
            }
            _finalizeCompletion(self); // finalize from the completion queue
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                _network_endBackgroundTask(self);
            });
        }
    };

    if (self->_callbackQueue == self->_completionQueue) {
        dispatch_barrier_async(self->_completionQueue, block);
    } else {
        // dispatch to callback queue to flush the callback queue
        dispatch_barrier_async(self->_callbackQueue, ^{
            // dispatch to completion queue for completion
            dispatch_barrier_async(self->_completionQueue, block);
        });
    }
}

static void _finalizeCompletion(SELF_ARG)
{
    if (!self) {
        return;
    }

    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&self->_didCompleteFinishedCallback, true);
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

static NSString *_createLogContextString(SELF_ARG,
                                         TNLRequestOperationState state,
                                         TNLResponse * __nullable response)
{
    TNLAssert(self);
    if (!self) {
        return nil;
    }

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

static TNLResponse *_network_finalizeResponse(SELF_ARG,
                                              TNLResponseInfo *responseInfo,
                                              NSError * __nullable responseError,
                                              TNLAttemptMetaData * __nullable metadata,
                                              NSURLSessionTaskMetrics * __nullable taskMetrics)
{
    TNLAssert(self);
    if (!self) {
        return nil;
    }

    _network_applyEncodingMetrics(self, responseInfo, metadata);
    [self->_metrics addMetaData:metadata taskMetrics:taskMetrics];

    // Capture any methods we are in when the timeout occurred
    if ([responseError.domain isEqualToString:TNLErrorDomain]) {
        switch (responseError.code) {
            case TNLErrorCodeRequestOperationAttemptTimedOut:
            case TNLErrorCodeRequestOperationIdleTimedOut:
            case TNLErrorCodeRequestOperationOperationTimedOut:
            case TNLErrorCodeRequestOperationCallbackTimedOut:
            {
                NSArray *tags = [self->_callbackTagStack copy];
                uint64_t mach_tagTime = self->_mach_callbackTagTime;
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

    TNLResponseMetrics *metrics = [self->_metrics deepCopyAndTrimIncompleteAttemptMetrics:NO];
    TNLResponse *response = [self.responseClass responseWithRequest:self->_originalRequest
                                                     operationError:responseError
                                                               info:responseInfo
                                                            metrics:metrics];
    TNLAssert(response != nil);
    return response;
}

static void _network_applyEncodingMetrics(SELF_ARG,
                                          TNLResponseInfo *responseInfo,
                                          TNLAttemptMetaData * __nullable metadata)
{
    if (self->_scratchURLRequestOriginalBodyLength > 0) {
        NSString *contentEncoding = [responseInfo.finalURLRequest valueForHTTPHeaderField:@"Content-Encoding"];
        if (contentEncoding) {
            metadata.requestContentLength = self->_scratchURLRequestEncodedBodyLength;
            metadata.requestOriginalContentLength = self->_scratchURLRequestOriginalBodyLength;
            metadata.requestEncodingLatency = self->_scratchURLRequestEncodeLatency;
        }
    }
}

#pragma mark Attempt Retry

static BOOL _network_shouldAttemptRetryDuringStateTransition(SELF_ARG,
                                                             TNLRequestOperationState oldState,
                                                             TNLRequestOperationState state,
                                                             TNLResponse * __nullable attemptResponse)
{
    if (!self) {
        return NO;
    }

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

    if (_network_getHasFailed(self)) {
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

static BOOL _network_shouldForciblyRetryInvalidatedURLSessionRequest(SELF_ARG,
                                                                     TNLResponse *attemptResponse)
{
    if (!self) {
        return NO;
    }

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
                               (self->_backgroundFlags.invalidSessionRetryCount < maxInvalidSessionRetryCount);
    TNLLogWarning(@"Encountered a session invalidation error, %@ retrying.\nError: %@", (forciblyRetry) ? @"" : @" not", attemptResponse.operationError);
    return forciblyRetry;
}

static void _network_forciblyRetryInvalidatedURLSessionRequest(SELF_ARG,
                                                               TNLResponse *attemptResponse)
{
    if (!self) {
        return;
    }

    if (self->_cachedCancelError) {
        _network_fail(self, self->_cachedCancelError);
    } else {
        self->_backgroundFlags.invalidSessionRetryCount++;
        self.URLSessionTaskOperation = nil;
        self->_backgroundFlags.silentStart = 1;
        _network_transitionState(self,
                                 TNLRequestOperationStateWaitingToRetry,
                                 nil /*attemptResponse*/);
        _network_startRetryTimer(self,
                                 MIN_TIMER_INTERVAL,
                                 attemptResponse,
                                 nil /*retryPolicyProvider*/);
        // don't need to end the background task here since we are triggering
        // the retry in order to circumvent a race condition that causes a failure,
        // not actually retrying after a legitimate failure that could be of any
        // duration.
    }
}

static void _network_attemptRetryDuringStateTransition(SELF_ARG,
                                                       TNLRequestOperationState oldState,
                                                       TNLRequestOperationState state,
                                                       TNLResponse * __nullable attemptResponse)
{
    if (!self) {
        return;
    }

    if (self->_backgroundFlags.inRetryCheck) {
        return;
    }

    const BOOL shouldAttemptRetry = _network_shouldAttemptRetryDuringStateTransition(self,
                                                                                     oldState,
                                                                                     state,
                                                                                     attemptResponse);

    if (shouldAttemptRetry && [attemptResponse.operationError.domain isEqualToString:TNLErrorDomain] && attemptResponse.operationError.code == TNLErrorCodeRequestOperationURLSessionInvalidated) {
        // Invalidated session, we have special logic for this case
        if (_network_shouldForciblyRetryInvalidatedURLSessionRequest(self, attemptResponse)) {
            _network_forciblyRetryInvalidatedURLSessionRequest(self, attemptResponse);
            return;
        }
    }

    const id<TNLRequestRetryPolicyProvider> retryPolicyProvider = self->_requestConfiguration.retryPolicyProvider;
    if (!shouldAttemptRetry || !retryPolicyProvider || ![retryPolicyProvider respondsToSelector:@selector(tnl_shouldRetryRequestOperation:withResponse:)]) {
        // early check, not going to retry
        _network_completeStateTransition(self,
                                         oldState,
                                         state,
                                         attemptResponse);
        return;
    }

    _network_retryDuringStateTransition(self,
                                        oldState,
                                        state,
                                        attemptResponse,
                                        retryPolicyProvider);
}

static void _network_retryDuringStateTransition(SELF_ARG,
                                                TNLRequestOperationState oldState,
                                                TNLRequestOperationState state,
                                                TNLResponse *attemptResponse,
                                                id<TNLRequestRetryPolicyProvider> retryPolicyProvider)
{
    if (!self) {
        return;
    }

    TNLAssert(retryPolicyProvider != nil);
    TNLAssert(!self->_backgroundFlags.inRetryCheck);

    self->_backgroundFlags.inRetryCheck = YES;

    const BOOL hasCachedCancel = self->_cachedCancelError != nil;
    const id<TNLRequestEventHandler> eventHandler = self.internalDelegate;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    const uint64_t enqueueMachTime = self->_metrics.enqueueMachTime;
#pragma clang diagnostic pop
    TNLRequestConfiguration *requestConfig = self->_requestConfiguration;

    // Dispatch to the retry queue to get retry policy info
    dispatch_barrier_async(_RetryPolicyProviderQueue(retryPolicyProvider), ^{

        @autoreleasepool {
            NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), @selector(tnl_shouldRetryRequestOperation:withResponse:));
            _updateTag(self, tag);
            const BOOL retry = [retryPolicyProvider tnl_shouldRetryRequestOperation:self
                                                                       withResponse:attemptResponse];
            _clearTag(self, tag);

            if (retry) {

                NSTimeInterval operationTimeout = requestConfig.operationTimeout;
                BOOL didUpdateOperationTimeout = NO;
                TNLRequestConfiguration *newConfig = _retryQueue_pullNewRequestConfiguration(self,
                                                                                             retryPolicyProvider,
                                                                                             attemptResponse,
                                                                                             requestConfig);
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

                const NSTimeInterval retryDelay = _retryQueue_pullRetryDelay(self, retryPolicyProvider, attemptResponse);
                const NSTimeInterval elapsedTime = TNLComputeDuration(enqueueMachTime, mach_absolute_time());

                // Only retry if the attempt won't be too far into the future
                if ((elapsedTime + retryDelay) < operationTimeout) {
                    TNLLogDebug(@"Retry will start in %.3f seconds", retryDelay);

                    NSTimeInterval newOperationTimeout = -1.0; // negative won't update timeout
                    if (didUpdateOperationTimeout) {
                        newOperationTimeout = operationTimeout - elapsedTime;
                        TNLAssert(newOperationTimeout >= 0.0);
                    }
                    _retryQueue_doRetry(self,
                                        oldState,
                                        retryPolicyProvider,
                                        attemptResponse,
                                        retryDelay,
                                        eventHandler,
                                        hasCachedCancel,
                                        newConfig,
                                        newOperationTimeout);
                    return;
                }

                TNLLogDebug(@"Retry is past timeout, not retrying");
            }

            // won't retry
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                self->_backgroundFlags.inRetryCheck = NO;
                if (_network_getIsStateFinished(self)) {
                    return;
                }

                TNLAssert(attemptResponse != nil);
                _network_completeStateTransition(self,
                                                 oldState,
                                                 state,
                                                 attemptResponse);
            });
        }
    });
}

#pragma mark Retry Static Functions

static NSTimeInterval _retryQueue_pullRetryDelay(SELF_ARG,
                                                 id<TNLRequestRetryPolicyProvider> retryPolicyProvider,
                                                 TNLResponse *attemptResponse)
{
    if (!self) {
        return MIN_TIMER_INTERVAL;
    }

    // get retry delay from retry policy provider
    const SEL delayCallback = @selector(tnl_delayBeforeRetryForRequestOperation:withResponse:);
    NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), delayCallback);
    _updateTag(self, tag);
    NSTimeInterval retryDelay = 0.0;
    if ([retryPolicyProvider respondsToSelector:delayCallback]) {
        retryDelay = [retryPolicyProvider tnl_delayBeforeRetryForRequestOperation:self
                                                                     withResponse:attemptResponse];
    }
    _clearTag(self, tag);

    if (retryDelay < MIN_TIMER_INTERVAL) {
        retryDelay = MIN_TIMER_INTERVAL;
    }

    return retryDelay;
}

static TNLRequestConfiguration * __nullable _retryQueue_pullNewRequestConfiguration(SELF_ARG,
                                                                                    id<TNLRequestRetryPolicyProvider> retryPolicyProvider,
                                                                                    TNLResponse *attemptResponse,
                                                                                    TNLRequestConfiguration *oldConfig)
{
    if (!self) {
        return nil;
    }

    TNLRequestConfiguration *newConfig = nil;

    // get new request config from retry policy provider and update _requestConfiguration_ if necessary
    const SEL newConfigCallback = @selector(tnl_configurationOfRetryForRequestOperation:withResponse:priorConfiguration:);
    if ([retryPolicyProvider respondsToSelector:newConfigCallback]) {
        NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), newConfigCallback);
        _updateTag(self, tag);
        newConfig = [[retryPolicyProvider tnl_configurationOfRetryForRequestOperation:self
                                                                         withResponse:attemptResponse
                                                                   priorConfiguration:oldConfig] copy];
        _clearTag(self, tag);

        if (newConfig && newConfig == oldConfig) {
            newConfig = nil;
        }
    }

    return newConfig;
}

static void _retryQueue_doRetry(SELF_ARG,
                                TNLRequestOperationState oldState,
                                id<TNLRequestRetryPolicyProvider> retryPolicyProvider,
                                TNLResponse *attemptResponse,
                                NSTimeInterval retryDelay,
                                id<TNLRequestEventHandler> eventHandler,
                                BOOL hasCachedCancel,
                                TNLRequestConfiguration *newConfig,
                                NSTimeInterval newOperationTimeout)
{
    if (!self) {
        return;
    }

    SEL willStartRetryCallback = @selector(tnl_requestOperation:willStartRetryFromResponse:afterDelay:);
    if (!hasCachedCancel) {
        if ([retryPolicyProvider respondsToSelector:willStartRetryCallback]) {
            NSString *tag = TAG_FROM_METHOD(retryPolicyProvider, @protocol(TNLRequestRetryPolicyProvider), willStartRetryCallback);
            _updateTag(self, tag);
            [retryPolicyProvider tnl_requestOperation:self
                           willStartRetryFromResponse:attemptResponse
                                           afterDelay:retryDelay];
            _clearTag(self, tag);
        }
    }

    if (newConfig) {
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            // update the config
            self->_requestConfiguration = newConfig;
            // update the operation timeout if it had changed
            if (newOperationTimeout > 0) {
                _network_invalidateOperationTimeoutTimer(self);
                _network_startOperationTimeoutTimer(self, newOperationTimeout);
            }
        });
    }

    // Dispatch to the callback queue in case we need to event to the event handler
    willStartRetryCallback = @selector(tnl_requestOperation:willStartRetryFromResponse:policyProvider:afterDelay:);
    dispatch_barrier_async(self->_callbackQueue, ^{
        @autoreleasepool {
            if (!hasCachedCancel) {
                if ([eventHandler respondsToSelector:willStartRetryCallback] && ((__bridge void *)eventHandler != (__bridge void *)retryPolicyProvider)) {
                    NSString *eventTag = TAG_FROM_METHOD(eventHandler, @protocol(TNLRequestEventHandler), willStartRetryCallback);
                    _updateTag(self, eventTag);
                    [eventHandler tnl_requestOperation:self
                            willStartRetryFromResponse:attemptResponse
                                        policyProvider:retryPolicyProvider
                                            afterDelay:retryDelay];
                    _clearTag(self, eventTag);
                }
            }

            // Finish with dispatch to background queue to update state and start retry timer (if necessary)
            tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
                self->_backgroundFlags.inRetryCheck = NO;
                if (_network_getHasFailedOrFinished(self)) {
                    return;
                }

                // don't use stale hasCachedCancel var here,
                // check the fresh _cachedCancel ref directly
                if (self->_cachedCancelError != nil) {
                    _network_fail(self, self->_cachedCancelError);
                } else {
                    self.URLSessionTaskOperation = nil;
                    TNLRequestOperationState updatedOldState = oldState;
                    if (TNLRequestOperationStatePreparingRequest == oldState) {
                        // forcibly update to "Starting" before updating to "Waiting to Retry"
                        _network_completeStateTransition(self,
                                                         oldState,
                                                         TNLRequestOperationStateStarting,
                                                         nil /*attemptResponse*/);
                        updatedOldState = TNLRequestOperationStateStarting;
                    }
                    _network_completeStateTransition(self,
                                                     updatedOldState,
                                                     TNLRequestOperationStateWaitingToRetry,
                                                     attemptResponse);
                    _network_startRetryTimer(self,
                                             retryDelay,
                                             attemptResponse,
                                             retryPolicyProvider);
                    // end the background task while waiting to retry,
                    // we only want the active request to be guarded with a bg task
                    _network_endBackgroundTask(self);
                }
            });
        }
    });
}

#pragma mark Retry Timer

static void _network_startRetryTimer(SELF_ARG,
                                     NSTimeInterval retryInterval,
                                     TNLResponse *oldResponse,
                                     id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider)
{
    if (!self) {
        return;
    }

    _network_invalidateRetryTimer(self);

    if (retryInterval < MIN_TIMER_INTERVAL) {
        _network_retryTimerDidFire(self,
                                   oldResponse,
                                   retryPolicyProvider);
    } else {
        __weak typeof(self) weakSelf = self;
        self->_retryDelayTimerSource = tnl_dispatch_timer_create_and_start(tnl_network_queue(),
                                                                           retryInterval,
                                                                           TIMER_LEEWAY_WITH_FIRE_INTERVAL(retryInterval),
                                                                           NO /*repeats*/,
                                                                           ^{
            _network_retryTimerDidFire(weakSelf,
                                       oldResponse,
                                       retryPolicyProvider);
        });
    }
}

static void _network_invalidateRetryTimer(SELF_ARG)
{
    if (!self) {
        return;
    }

    tnl_dispatch_timer_invalidate(self->_retryDelayTimerSource);
    self->_retryDelayTimerSource = NULL;
}

static void _network_retryTimerDidFire(SELF_ARG,
                                       TNLResponse *oldResponse,
                                       id<TNLRequestRetryPolicyProvider> __nullable retryPolicyProvider)
{
    if (!self) {
        return;
    }

    if (self->_retryDelayTimerSource) {
        TNLLogInformation(@"%@::_network_retryTimerDidFire()", self);

        _network_invalidateRetryTimer(self);
        _network_retry(self, oldResponse, retryPolicyProvider);
    }
}

#pragma mark Operation Timeout Timer

static void _network_startOperationTimeoutTimer(SELF_ARG,
                                                NSTimeInterval timeInterval)
{
    if (!self) {
        return;
    }

    if (!self->_operationTimeoutTimerSource && timeInterval >= MIN_TIMER_INTERVAL) {
        __weak typeof(self) weakSelf = self;
        self->_operationTimeoutTimerSource = tnl_dispatch_timer_create_and_start(tnl_network_queue(),
                                                                                 timeInterval,
                                                                                 TIMER_LEEWAY_WITH_FIRE_INTERVAL(timeInterval),
                                                                                 NO /*repeats*/,
                                                                                 ^{
            _network_operationTimeoutTimerDidFire(weakSelf);
        });
    }
}

static void _network_invalidateOperationTimeoutTimer(SELF_ARG)
{
    if (!self) {
        return;
    }

    tnl_dispatch_timer_invalidate(self->_operationTimeoutTimerSource);
    self->_operationTimeoutTimerSource = NULL;
}

static void _network_operationTimeoutTimerDidFire(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (self->_operationTimeoutTimerSource) {
        TNLLogInformation(@"%@::_network_operationTimeoutTimerDidFire()", self);

        _network_invalidateOperationTimeoutTimer(self);
        _network_invalidateAttemptTimeoutTimer(self);
        _network_invalidateRetryTimer(self);

        if (!_network_getHasFailedOrFinished(self)) {
            _network_fail(self, TNLErrorCreateWithCode(TNLErrorCodeRequestOperationOperationTimedOut));
        }
    }
}

#pragma mark Callback Timeout Timer

static void _network_startCallbackTimer(SELF_ARG,
                                        NSTimeInterval alreadyElapsedTime)
{
    if (!self) {
        return;
    }

    TNLAssert(!self->_callbackTimeoutTimerSource);

    if (self->_backgroundFlags.isCallbackClogDetectionEnabled) {

#if TARGET_OS_IOS || TARGET_OS_TV
        if (!TNLIsExtension()) {

            // Lazily prep our app backgrounding observing
            if (!self->_backgroundFlags.isObservingApplicationStates) {
                _network_startObservingApplicationStates(self);
            }

            if (self->_backgroundFlags.applicationIsInBackground) {
                // already in the background or is inactive!  Set our mach times.
                self->_callbackTimeoutTimerStartMachTime = self->_callbackTimeoutTimerPausedMachTime = mach_absolute_time();
                return;
            }
        }
#endif // IOS + TV

        __weak typeof(self) weakSelf = self;
        self->_callbackTimeoutTimerSource = tnl_dispatch_timer_create_and_start(tnl_network_queue(),
                                                                                self->_cloggedCallbackTimeout - alreadyElapsedTime,
                                                                                TIMER_LEEWAY_WITH_FIRE_INTERVAL(self->_cloggedCallbackTimeout),
                                                                                NO /*repeats*/,
                                                                                ^{
            _network_callbackTimerFired(weakSelf);
        });
        self->_callbackTimeoutTimerStartMachTime = mach_absolute_time() - TNLAbsoluteFromTimeInterval(alreadyElapsedTime);
    }
}

static void _network_stopCallbackTimer(SELF_ARG)
{
    if (!self) {
        return;
    }

    tnl_dispatch_timer_invalidate(self->_callbackTimeoutTimerSource);
    self->_callbackTimeoutTimerSource = NULL;
    self->_callbackTimeoutTimerPausedMachTime = 0;
}

static void _network_startCallbackTimerIfNecessary(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (!self->_callbackTimeoutTimerSource) {
        _network_startCallbackTimer(self, 0.0 /*alreadyElapsedTime*/);
    }
}

static void _network_callbackTimerFired(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (self->_callbackTimeoutTimerSource) {
        _network_stopCallbackTimer(self);
        if (!_network_getHasFailedOrFinished(self)) {
            _network_fail(self, TNLErrorCreateWithCode(TNLErrorCodeRequestOperationCallbackTimedOut));
        }
    }
}

#if TARGET_OS_IOS || TARGET_OS_TV
static void _network_pauseCallbackTimer(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (self->_callbackTimeoutTimerSource) {
        _network_stopCallbackTimer(self);
        self->_callbackTimeoutTimerPausedMachTime = mach_absolute_time();
    }
}

static void _network_unpauseCallbackTimer(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (self->_callbackTimeoutTimerPausedMachTime) {
        const NSTimeInterval timeElapsed = TNLComputeDuration(self->_callbackTimeoutTimerStartMachTime,
                                                              self->_callbackTimeoutTimerPausedMachTime);
        self->_callbackTimeoutTimerPausedMachTime = 0;
        _network_startCallbackTimer(self, timeElapsed);
    }
}
#endif // IOS + TV

#pragma mark Attempt Timeout Timer

static void _network_startAttemptTimeoutTimer(SELF_ARG,
                                              NSTimeInterval timeInterval)
{
    if (!self) {
        return;
    }

    if (!self->_attemptTimeoutTimerSource && timeInterval >= MIN_TIMER_INTERVAL) {
        __weak typeof(self) weakSelf = self;
        self->_attemptTimeoutTimerSource = tnl_dispatch_timer_create_and_start(tnl_network_queue(),
                                                                               timeInterval,
                                                                               TIMER_LEEWAY_WITH_FIRE_INTERVAL(timeInterval),
                                                                               NO /*repeats*/,
                                                                               ^{
            _network_attemptTimeoutTimerDidFire(weakSelf);
        });
    }
}

static void _network_invalidateAttemptTimeoutTimer(SELF_ARG)
{
    if (!self) {
        return;
    }

    tnl_dispatch_timer_invalidate(self->_attemptTimeoutTimerSource);
    self->_attemptTimeoutTimerSource = NULL;
}

static void _network_attemptTimeoutTimerDidFire(SELF_ARG)
{
    if (!self) {
        return;
    }

    if (self->_attemptTimeoutTimerSource) {
        TNLLogInformation(@"%@::_network_attemptTimeoutTimerDidFire()", self);

        _network_invalidateAttemptTimeoutTimer(self);
        _network_invalidateRetryTimer(self);
        // Don't invalidate the operation timeout

        if (!_network_getHasFailedOrFinished(self)) {
            _network_fail(self, TNLErrorCreateWithCode(TNLErrorCodeRequestOperationAttemptTimedOut));
        }
    }
}

#pragma mark Background (iOS)

static void _noop(SELF_ARG)
{
}

- (void)_private_willResignActive:(NSNotification *)note
{
    TNLGlobalConfiguration *config = [TNLGlobalConfiguration sharedInstance];
    TNLBackgroundTaskIdentifier taskID = [config startBackgroundTaskWithName:@"-[TNLRequestOperation private_willResignActive:]"
                                                           expirationHandler:^{
        // capture self
        _noop(self);
    }];
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        _network_willResignActive(self);
        [config endBackgroundTaskWithIdentifier:taskID];
    });
}

- (void)_private_didBecomeActive:(NSNotification *)note
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        _network_didBecomeActive(self);
    });
}

static void _network_willResignActive(SELF_ARG)
{
    if (!self) {
        return;
    }

#if TARGET_OS_IOS || TARGET_OS_TV
    self->_backgroundFlags.applicationIsInBackground = 1;
    _network_pauseCallbackTimer(self);
#endif
}

static void _network_didBecomeActive(SELF_ARG)
{
    if (!self) {
        return;
    }

#if TARGET_OS_IOS || TARGET_OS_TV
    self->_backgroundFlags.applicationIsInBackground = 0;
    _network_unpauseCallbackTimer(self);
#endif
}

#if TARGET_OS_IOS || TARGET_OS_TV
static void _network_startObservingApplicationStates(SELF_ARG)
{
    if (!self) {
        return;
    }

    TNLAssert(!self->_backgroundFlags.isObservingApplicationStates);
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
        self->_backgroundFlags.applicationIsInBackground = 1;
    } else {
        self->_backgroundFlags.applicationIsInBackground = 0;
    }

    self->_backgroundFlags.isObservingApplicationStates = 1;
}
#endif // IOS + TV

#if TARGET_OS_IOS || TARGET_OS_TV
static void _dealloc_stopObservingApplicationStatesIfNecessary(SELF_ARG) TNL_THREAD_SANITIZER_DISABLED
{
    if (!self) {
        return;
    }

    if (self->_backgroundFlags.isObservingApplicationStates) {
        TNLAssert(!TNLIsExtension());
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc removeObserver:self
                      name:UIApplicationWillResignActiveNotification
                    object:nil];
        [nc removeObserver:self
                      name:UIApplicationDidBecomeActiveNotification
                    object:nil];
        self->_backgroundFlags.isObservingApplicationStates = 0;
    }
}
#endif // IOS + TV

static void _network_startBackgroundTask(SELF_ARG)
{
#if TARGET_OS_IOS || TARGET_OS_TV
    if (!self) {
        return;
    }

    if (TNLBackgroundTaskInvalid != self->_backgroundTaskIdentifier) {
        return;
    }

    self->_backgroundTaskIdentifier = [[TNLGlobalConfiguration sharedInstance] startBackgroundTaskWithName:@"tnl.request.op"
                                                                                         expirationHandler:^{
        dispatch_sync(tnl_network_queue(), ^{
            self->_backgroundTaskIdentifier = TNLBackgroundTaskInvalid;
        });
    }];
#endif // IOS + TV
}

static void _network_endBackgroundTask(SELF_ARG)
{
#if TARGET_OS_IOS || TARGET_OS_TV
    if (!self) {
        return;
    }

    if (TNLBackgroundTaskInvalid == self->_backgroundTaskIdentifier) {
        return;
    }

    [[TNLGlobalConfiguration sharedInstance] endBackgroundTaskWithIdentifier:self->_backgroundTaskIdentifier];
    self->_backgroundTaskIdentifier = TNLBackgroundTaskInvalid;
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

static void _updateTag(SELF_ARG,
                       NSString *tag)
{
    if (!self) {
        return;
    }

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (!self->_mach_callbackTagTime) {
            self->_mach_callbackTagTime = mach_absolute_time();
        }
        [self->_callbackTagStack addObject:tag];
        _network_startCallbackTimerIfNecessary(self);
    });
}

static void _clearTag(SELF_ARG,
                      NSString *tag)
{
    if (!self) {
        return;
    }

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self->_callbackTagStack removeObject:tag];
        if (self->_callbackTagStack.count == 0) {
            self->_mach_callbackTagTime = 0;
            _network_stopCallbackTimer(self);
        }
    });
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

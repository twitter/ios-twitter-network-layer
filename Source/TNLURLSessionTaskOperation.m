//
//  TNLURLSessionTaskOperation.m
//  TwitterNetworkLayer
//
//  Created on 6/11/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#include <mach/mach_time.h>
#include <objc/runtime.h>
#include <stdatomic.h>

#import <CommonCrypto/CommonDigest.h>

#import "NSCachedURLResponse+TNLAdditions.h"
#import "NSData+TNLAdditions.h"
#import "NSDictionary+TNLAdditions.h"
#import "NSURLResponse+TNLAdditions.h"
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "NSURLSessionTaskMetrics+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLAttemptMetaData_Project.h"
#import "TNLAttemptMetrics.h"
#import "TNLBackoff.h"
#import "TNLContentCoding.h"
#import "TNLError.h"
#import "TNLGlobalConfiguration.h"
#import "TNLHTTPHeaderProvider.h"
#import "TNLNetwork.h"
#import "TNLPriority.h"
#import "TNLRequest.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLRequestOperation_Project.h"
#import "TNLRequestOperationQueue_Project.h"
#import "TNLResponse_Project.h"
#import "TNLTemporaryFile_Project.h"
#import "TNLTiming.h"
#import "TNLURLSessionTaskOperation.h"

NS_ASSUME_NONNULL_BEGIN

#define EXTRA_DOWNLOAD_BYTES_BUFFER (16)

#define kTaskMetricsNotSeenOnCompletionDelayCompletionDuration (0.300)

static NSString * const kTempFilePrefix = @"com.tnl.temp.";

static NSString *TNLWriteDataToTemporaryFile(NSData *data);
static BOOL TNLURLRequestHasBody(NSURLRequest *request, id<TNLRequest> requestPrototype);
static NSArray<NSString *> *TNLSecTrustGetCertificateChainDescriptions(SecTrustRef trust);
static NSString *TNLSecCertificateDescription(SecCertificateRef cert);

TNL_OBJC_FINAL TNL_OBJC_DIRECT_MEMBERS
@interface TNLFakeRequestOperation : TNLRequestOperation
- (instancetype)initWithURLSessionTaskOperation:(TNLURLSessionTaskOperation *)op NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithRequest:(nullable id<TNLRequest>)request
                  configuration:(nullable TNLRequestConfiguration *)config
                       delegate:(nullable id<TNLRequestDelegate>)delegate NS_UNAVAILABLE;
@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLURLSessionTaskOperation () <TNLContentDecoderClient>

@property (nonatomic, readonly) TNLRequestOperationState state;
@property (nonatomic, readonly, getter=isComplete) BOOL complete;
@property (nonatomic, readonly, getter=isFinalizing) BOOL finalizing;

@property (nonatomic, readonly, nullable) NSDictionary<NSString *, id<TNLContentDecoder>> *additionalDecoders;
@property (nonatomic, readonly, nullable) id<TNLContentDecoder> contentDecoder;
@property (nonatomic, readonly, nullable) id<TNLContentDecoderContext> contentDecoderContext;
@property (nonatomic, readonly, nullable) NSMutableData *contentDecoderRecentData;
@property (nonatomic) id<TNLRequest> originalRequest;

- (BOOL)_currentRequestHasBody;

#pragma mark Decoding

- (void)_decodeData:(NSData *)data
         completion:(void(^)(NSData * __nullable decodedData, NSError * __nullable decodeError))blockName; // completion called on bg queue
- (void)_finishDecodingWithURLSession:(NSURLSession *)completedURLSession
                             dataTask:(NSURLSessionDataTask *)dataTask;
- (void)_network_flushDecoding:(nullable NSError *)error
                    completion:(void(^)(NSData * __nullable decodedData, NSError * __nullable decodeError))completion;
- (void)_network_didDecodeData:(nullable NSData *)decodedData
                    URLSession:(NSURLSession *)session
                      dataTask:(NSURLSessionDataTask *)dataTask
                         error:(nullable NSError *)decodeError;

#pragma mark Network

// TODO: move these all to (Network) category

- (void)_network_finalizeDidCompleteTask:(NSURLSessionTask *)task
                              URLSession:(NSURLSession *)session
                                   error:(nullable NSError *)error;

// NSURLSession Events
- (void)_network_willPerformHTTPRedirectionFromRequest:(NSURLRequest *)fromRequest
                                              response:(NSHTTPURLResponse *)response
                                       originalRequest:(NSURLRequest *)originalRequest
                                      suggestedRequest:(NSURLRequest *)suggestedRequest
                                         chosenRequest:(nullable id<TNLRequest>)chosenRequest
                                            completion:(void(^)(NSURLRequest * __nullable))completionHandler;
- (void)_network_handleRedirectFromRequest:(NSURLRequest *)fromRequest
                                  response:(NSHTTPURLResponse *)response
                                 toRequest:(nullable NSURLRequest *)toRequest
                                completion:(void(^)(NSURLRequest * __nullable))completionHandler;

@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLURLSessionTaskOperation (Network)

// Methods that can only be called from the tnl_network_queue()

#pragma mark Properties

- (float)_network_uploadProgress;
- (float)_network_downloadProgress;

#pragma mark NSOperation

- (BOOL)_network_shouldCancel;

#pragma mark Update State

- (void)_network_updatePriorities;
- (void)_network_updateUploadProgress:(float)progress;
- (void)_network_updateDownloadProgress:(float)progress;
- (void)_network_transitionToState:(TNLRequestOperationState)state;
- (void)_network_updateTimestampsWithState:(TNLRequestOperationState)state;
- (void)_network_buildResponseInfo;
- (void)_network_buildInternalResponse;
- (void)_network_finalizeWithState:(TNLRequestOperationState)state;
- (void)_network_finalizeWithResponseCompletion:(TNLRequestMakeFinalResponseCompletionBlock)completion;

#pragma mark Completion/Failure/Cancel

- (void)_network_fail:(NSError *)error;
- (void)_network_cancel;
- (void)_network_complete;
- (void)_network_completeCachedCompletionIfPossible;

#pragma mark NSURLSession Events

- (void)_network_didUpdateTotalBytesReceived:(int64_t)bytesReceived
                               expectedBytes:(int64_t)totalBytesExpectedToReceive
                                  URLSession:(NSURLSession *)session
                                downloadTask:(NSURLSessionDownloadTask *)downloadTask;
- (void)_network_captureResponseFromTaskIfNeeded:(NSURLSessionTask *)task
                                      URLSession:(NSURLSession *)session;
- (void)_network_didReceiveResponse:(NSURLResponse *)response
                         URLSession:(NSURLSession *)session
                               task:(NSURLSessionTask *)task;

#pragma mark NSURLSessionTask Methods

- (void)_network_willResumeSessionTaskWithRequest:(NSURLRequest *)resumeRequest;
- (void)_network_resumeSessionTask:(NSURLSessionTask *)task;
- (void)_network_createTaskWithRequest:(NSURLRequest *)request
                             prototype:(id<TNLRequest>)requestPrototype
                            completion:(void(^)(NSURLSessionTask *createdTask, NSError *error))complete;
- (nullable NSURLSessionTask *)_network_populateURLSessionTaskWithRequest:(NSURLRequest *)request
                                                                prototype:(id<TNLRequest>)requestPrototype
                                                                    error:(out NSError * __nullable * __nonnull)errorOut;

#pragma mark Other Methods

- (nullable NSError *)_network_appendDecodedData:(nullable NSData *)data;
- (void)_network_didStartTask:(BOOL)isBackgroundRequest;
- (void)_network_updateHashWithData:(NSData *)data;
- (void)_network_finishHashWithSuccess:(BOOL)success;

#pragma mark Idle Timeout

- (void)_network_startIdleTimerWithDeferralDuration:(NSTimeInterval)deferral;
- (void)_network_stopIdleTimer;
- (void)_network_restartIdleTimer;
- (void)_network_idleTimerFired;

@end

#pragma mark - TNLURLSessionTaskOperation

@implementation TNLURLSessionTaskOperation
{
    // Session/Task State

    __unsafe_unretained id<TNLURLSessionManager> _sessionManager;
    NSURLSession *_URLSession;
    NSURLSessionDataTask *_dataTask;
    NSURLSessionDownloadTask *_downloadTask;
    NSURLSessionUploadTask *_uploadTask;
    NSURLRequest *_taskRequest;
    NSData *_uploadData;
    NSString *_uploadFilePath;
    NSData *_resumeData; // TODO:[nobrien] - utilize

    // Request/Response iVars

    id<TNLRequest> _hydratedRequest;
    Class _responseClass;

    // Timings

    NSDate *_startDate;
    uint64_t _startMachTime; // deprecated
    NSDate *_endDate;
    uint64_t _endMachTime; // deprecated
    NSDate *_completeDate;
    uint64_t _completeMachTime; // deprecated

    TNLPriority _taskResumePriority;
    NSDate *_taskResumeDate;
    NSDate *_responseBodyStartDate;
    NSDate *_responseBodyEndDate;
    NSDate *_completionCallbackDate;
    NSDate *_taskMetricsCallbackDate;

    // Timers

    dispatch_source_t _idleTimer;

    // Cached State

    NSError *_cachedFailure;
    NSHTTPURLResponse *_cancelledRedirectResponse;
    NSURLSession *_cachedCompletionSession;
    NSURLSessionTask *_cachedCompletionTask;
    NSError *_cachedCompletionError;

    // Gathered State

    void *_hashContextRef;
    NSData *_hashData;
    TNLResponseHashComputeAlgorithm _hashAlgo;
    NSDictionary *_authChallengeCancelledUserInfo;
    NSMutableData *_storedData;
    TNLTemporaryFile *_tempFile;
    SInt64 _layer8BodyBytesReceived; // count after uncompressing

    // Metrics

    NSTimeInterval _responseDecodeLatency;
    NSURLSessionTaskMetrics *_taskMetrics;

    // State

    TNLRequestOperationState_AtomicT _internalState;

    struct {
        BOOL didCancel:1;
        BOOL didStart:1;
        BOOL didIncrementExecutionCount:1;
        BOOL shouldComputeHash:1;
        BOOL isComputingHash:1;
        BOOL isFinalizing:1;
        BOOL useIdleTimeout:1;
        BOOL useIdleTimeoutForInitialConnection:1;
        BOOL shouldCaptureResponse:1;
        BOOL encounteredCompletionBeforeTaskMetrics:1;
        BOOL shouldDeleteUploadFile:1;
    } _flags;

    volatile BOOL _isObservingURLSessionTask;
}

#pragma mark Description

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p: originalURL='%@'>", NSStringFromClass([self class]), self, self.originalRequest.URL];
}

#pragma mark init/dealloc

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (instancetype)init
#pragma clang diagnostic pop
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
    return nil;
}

- (instancetype)initWithRequestOperation:(TNLRequestOperation *)op
                          sessionManager:(id<TNLURLSessionManager>)sessionManager
{
    if (self = [super init]) {
        TNLIncrementObjectCount([self class]);

        _sessionManager = sessionManager;

        _originalRequest = op.originalRequest;
        _hydratedRequest = op.hydratedRequest;
        _hydratedURLRequest = op.hydratedURLRequest;
        _requestConfiguration = op.requestConfiguration;
        _additionalDecoders = op.additionalDecoders;
        _executionMode = _requestConfiguration.executionMode;
        _requestOperation = op;
        _responseClass = op.responseClass;

        _hashAlgo = op.requestConfiguration.responseComputeHashAlgorithm;
        _flags.shouldComputeHash = (_hashAlgo != TNLResponseHashComputeAlgorithmNone);
        _flags.shouldCaptureResponse = 1;

        if (Nil == [NSURLSessionTaskMetrics class]) {
            // If task metrics don't exist (pre iOS 10 / macOS 10.12) we should not worry about collecting the metrics.
            // If there is no task metrics class, we can set that we've already "encountered" the metrics.
            _flags.encounteredCompletionBeforeTaskMetrics = 1;
        }

        TNLAssert(_hydratedRequest != nil);
        TNLAssert(_hydratedURLRequest != nil);
        TNLAssert(_requestConfiguration != nil);
        TNLAssert(op.URLSessionTaskOperation == nil);
        TNLAssert(![_requestConfiguration respondsToSelector:@selector(setExecutionMode:)] && "MUST be immutable");

        [self _network_updatePriorities];
    }
    return self;
}

- (void)dealloc
{
    TNLAssert(!_hashContextRef);

    [self _network_stopIdleTimer];
    if (!self.isComplete) {
        [self.URLSessionTask cancel];
    }

    TNLDecrementObjectCount([self class]);
}

#pragma mark Properties

- (TNLRequestOperationState)state
{
    return atomic_load(&_internalState);
}

- (BOOL)_currentRequestHasBody
{
    NSURLSessionTask *task = self.URLSessionTask;
    if ([task isKindOfClass:[NSURLSessionUploadTask class]]) {
        return YES;
    }

    return TNLURLRequestHasBody(task.currentRequest, _hydratedRequest);
}

- (nullable NSURLSessionTask *)URLSessionTask
{
    return _dataTask ?: _downloadTask ?: _uploadTask;
}

- (nullable NSHTTPURLResponse *)URLResponse
{
    return (NSHTTPURLResponse *)self.URLSessionTask.response ?: _cancelledRedirectResponse;
}

- (nullable NSURLRequest *)originalURLRequest
{
    NSURLRequest *request = self.URLSessionTask.originalRequest ?: _taskRequest;
    if (_uploadData && !request.HTTPBody) {
        NSMutableURLRequest *mRequest = [request mutableCopy];
        mRequest.HTTPBody = _uploadData;
        request = mRequest;
    }
    return [request copy];
}

- (nullable NSURL *)originalURL
{
    return self.URLSessionTask.originalRequest.URL;
}

- (nullable NSURLRequest *)currentURLRequest
{
    NSURLRequest *request = self.URLSessionTask.currentRequest;
    if (!request) {
        return self.originalURLRequest;
    }

    if (_uploadData && !request.HTTPBody) {
        NSMutableURLRequest *mRequest = [request mutableCopy];
        mRequest.HTTPBody = _uploadData;
        request = mRequest;
    }
    return [request copy];
}

- (nullable NSURL *)currentURL
{
    return self.URLSessionTask.currentRequest.URL;
}

- (TNLResponseSource)responseSource
{
    if (!self.URLSessionTask) {
        return TNLResponseSourceUnknown;
    }

    NSURLResponse *URLResponse = self.URLResponse;
    return (URLResponse.tnl_wasCachedResponse) ? TNLResponseSourceLocalCache : TNLResponseSourceNetworkRequest;
}

- (nullable NSURLSession *)URLSession
{
    return _URLSession;
}

- (void)setURLSession:(NSURLSession *)URLSession supportsTaskMetrics:(BOOL)taskMetrics
{
    TNLAssert(URLSession != nil);
    _URLSession = URLSession;
    if (!taskMetrics) {
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            // Task metrics are explicity not supported
            self->_flags.encounteredCompletionBeforeTaskMetrics = 1;
        });
    }
}

#pragma mark Association

- (void)enqueueToOperationQueueIfNeeded:(TNLRequestOperationQueue *)requestOperationQueue
{
    if (_requestOperationQueue) {
        TNLAssert(_requestOperationQueue == requestOperationQueue);
        return;
    }

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (!self->_requestOperationQueue) {
            if (gTwitterNetworkLayerAssertEnabled) {
                TNLAssert(!self->_requestOperationQueue || self->_requestOperationQueue == requestOperationQueue);
                TNLRequestOperation *strongRequestOp = self->_requestOperation;
                if (strongRequestOp) {
                    TNLAssert(strongRequestOp.requestOperationQueue == requestOperationQueue);
                }
            }
            self->_requestOperationQueue = requestOperationQueue;
            if (!self.isExecuting && !self.isCancelled && !self.isFinished) {
                [self->_sessionManager syncAddURLSessionTaskOperation:self];
            }
        } else {
            TNLAssert(self->_requestOperationQueue == requestOperationQueue);
        }
    });
}

- (void)cancelWithSource:(nullable id)optionalSource
         underlyingError:(nullable NSError *)optionalUnderlyingError
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        TNLRequestOperation *strongRequestOp = self->_requestOperation;
        if (strongRequestOp) {
            [strongRequestOp cancelWithSource:optionalSource
                              underlyingError:optionalUnderlyingError];
        }
    });
}

- (void)dissassociateRequestOperation:(TNLRequestOperation *)op
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        TNLRequestOperation *strongRequestOp = self->_requestOperation;
        if (strongRequestOp == op) {
            TNLResponse *response = strongRequestOp.response;
            self->_requestOperation = nil;
            if (response) {
                self->_finalResponse = response;
            }

            if ([self _network_shouldCancel]) {
                [self _network_cancel];
            } else {
                [self _network_updatePriorities];
            }
        }
    });
}

- (TNLRequestOperation *)synthesizeRequestOperation
{
    return [[TNLFakeRequestOperation alloc] initWithURLSessionTaskOperation:self];
}

#pragma mark Helpers

- (void)network_priorityDidChangeForRequestOperation:(TNLRequestOperation *)op
{
    TNLRequestOperation *requestOperation = _requestOperation;
    if (requestOperation == op) {
        [self _network_updatePriorities];
    }
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

- (BOOL)isFinalizing
{
    return _flags.isFinalizing;
}

- (BOOL)isComplete
{
    return TNLRequestOperationStateIsFinal(atomic_load(&_internalState));
}

- (BOOL)isFinished
{
    return TNLRequestOperationStateIsFinal(atomic_load(&_internalState));
}

- (BOOL)isCancelled
{
    return TNLRequestOperationStateCancelled == atomic_load(&_internalState);
}

- (BOOL)isExecuting
{
    return TNLRequestOperationStateIsActive(atomic_load(&_internalState));
}

- (void)start
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        TNLAssert(!self->_flags.didStart);

        self->_flags.didStart = YES;

        if (self.isComplete || self.isFinalizing) {
            // Complete or completing
            return;
        }

        if (self->_cachedFailure) {
            // Already failed
            [self _network_fail:self->_cachedFailure];
            return;
        }

        if ([self _network_shouldCancel]) {
            // Should cancel
            [self _network_cancel];
            return;
        }

        // Starting

        [self _network_transitionToState:TNLRequestOperationStateStarting];

        TNLAssert(self->_URLSession != nil);
        NSURLRequest *taskRequest = self.hydratedURLRequest;

        // Assert session is correct

        if (gTwitterNetworkLayerAssertEnabled) {
            if (TNLRequestExecutionModeBackground == self->_executionMode) {
                // Background
                TNLAssert([self->_URLSession.sessionDescription rangeOfString:@"/Background?"].location != NSNotFound);
            } else {
                // InApp
                TNLAssert([self->_URLSession.sessionDescription rangeOfString:@"/InApp?"].location != NSNotFound);
            }
        }

        // Create task and start

        [self _network_createTaskWithRequest:taskRequest
                                   prototype:self.originalRequest
                                  completion:^(NSURLSessionTask *createdTask, NSError *error) {
            TNLAssert(createdTask == self.URLSessionTask);
            if (error) {
                TNLAssert(!createdTask);
                [self _network_fail:error];
            } else {
                NSURLRequest *currentURLRequest = self.currentURLRequest;
                TNLAssert(createdTask);
                TNLAssert(currentURLRequest);
                TNLAssert(self.originalURLRequest);

                if (TNLRequestExecutionModeBackground != self->_executionMode) {
                    TNLGlobalConfigurationIdleTimeoutMode mode = [TNLGlobalConfiguration sharedInstance].idleTimeoutMode;
                    self->_flags.useIdleTimeout = (mode != TNLGlobalConfigurationIdleTimeoutModeDisabled);
                    if (self->_flags.useIdleTimeout) {
                        self->_flags.useIdleTimeoutForInitialConnection = (mode == TNLGlobalConfigurationIdleTimeoutModeEnabledIncludingInitialConnection);
                    }
                }
                [self _network_willResumeSessionTaskWithRequest:currentURLRequest];
                [self _network_resumeSessionTask:createdTask];
                [self _network_didStartTask:(TNLRequestExecutionModeBackground == self->_executionMode) /*isBackgroundRequest*/];

                if (self->_flags.shouldDeleteUploadFile) {
                    [[NSFileManager defaultManager] removeItemAtPath:self->_uploadFilePath error:NULL];
                    self->_flags.shouldDeleteUploadFile = NO;
                }

                if (self->_flags.useIdleTimeoutForInitialConnection) {
                    [self _network_restartIdleTimer];
                }
            }
        }];
    });
}

#pragma mark NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
        didBecomeInvalidWithError:(nullable NSError *)error
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (self.isComplete || self.isFinalizing) {
            return;
        }

        // If error is nil, the session was explicitely invalidated
        TNLLogError(@"%@ %@", NSStringFromSelector(_cmd), error);
        [self _network_fail:TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationURLSessionInvalidated, error)];
    });
}

- (void)handler:(nullable id<TNLAuthenticationChallengeHandler>)handler
        didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
        forURLSession:(NSURLSession *)session
        context:(nullable id)cancelContext
{
    NSURLProtectionSpace *protectionSpace = challenge.protectionSpace;
    NSString *protectionSpaceHost = protectionSpace.host;
    NSURLRequest *currentRequest = self.currentURLRequest;
    NSArray<NSString *> *certDescriptions = TNLSecTrustGetCertificateChainDescriptions(protectionSpace.serverTrust);
    NSString *authMethod = protectionSpace.authenticationMethod;
    NSHTTPURLResponse *failedResponse = (id)challenge.failureResponse;
    if (failedResponse && ![failedResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        failedResponse = nil;
    }

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
        if (protectionSpaceHost) {
            userInfo[TNLErrorProtectionSpaceHostKey] = protectionSpaceHost;
        }
        if (currentRequest) {
            userInfo[TNLErrorRequestKey] = currentRequest;
        }
        if (authMethod) {
            userInfo[TNLErrorAuthenticationChallengeMethodKey] = authMethod;
        }
        if (challenge.protectionSpace.realm != nil) {
            userInfo[TNLErrorAuthenticationChallengeRealmKey] = challenge.protectionSpace.realm;
        }
        if (certDescriptions) {
            userInfo[TNLErrorCertificateChainDescriptionsKey] = certDescriptions;
        }
        if (cancelContext) {
            userInfo[TNLErrorAuthenticationChallengeCancelContextKey] = cancelContext;
        }
        if (failedResponse) {
            userInfo[TNLErrorResponseKey] = failedResponse;
            // ... and, if we have the cancelled response, cache it for completion handling
            self->_cancelledRedirectResponse = failedResponse;
        }
        self->_authChallengeCancelledUserInfo = [userInfo copy];
    });
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
        taskIsWaitingForConnectivity:(NSURLSessionTask *)task
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_restartIdleTimer];

        const TNLRequestConnectivityOptions options = self->_requestConfiguration.connectivityOptions;
        if (TNL_BITMASK_INTERSECTS_FLAGS(options, TNLRequestConnectivityOptionWaitForConnectivity)) {
            // continue
        } else if (TNL_BITMASK_INTERSECTS_FLAGS(options, TNLRequestConnectivityOptionWaitForConnectivityWhenRetryPolicyProvided) && self->_requestConfiguration.retryPolicyProvider != nil) {
            // continue
        } else {
            // force failure - not waiting for connectivity
            // this is the same error that would trigger if we didn't have waitsForConnectivity set
            [self _network_fail:[NSError errorWithDomain:NSURLErrorDomain
                                                    code:NSURLErrorNotConnectedToInternet
                                                userInfo:nil]];
            return;
        }

        TNLRequestOperation *requestOperation = self->_requestOperation;
        if (requestOperation) {
            [requestOperation network_URLSessionTaskOperationIsWaitingForConnectivity:self];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)toRequest
        completionHandler:(void (^)(NSURLRequest * __nullable))completionHandler
{
    NSURLRequest *fromRequest = task.currentRequest;
    NSURLRequest *originalRequest = task.originalRequest;

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{

        // redirects yield either a completion or a new attempt,
        // stop our idle timer (if we have one running)
        [self _network_stopIdleTimer];

        TNLRequestOperation *requestOperation = self->_requestOperation;
        if (requestOperation) {
            [requestOperation network_URLSessionTaskOperation:self
                               willPerformRedirectFromRequest:fromRequest
                                             withHTTPResponse:response
                                                    toRequest:toRequest
                                                   completion:^(id<TNLRequest> __nullable callbackRequest) {
                TNLAssertIsNetworkQueue();
                [self _network_willPerformHTTPRedirectionFromRequest:fromRequest
                                                            response:response
                                                     originalRequest:originalRequest
                                                    suggestedRequest:toRequest
                                                       chosenRequest:callbackRequest
                                                          completion:completionHandler];
            }];
        } else {
            [self _network_willPerformHTTPRedirectionFromRequest:fromRequest
                                                        response:response
                                                 originalRequest:originalRequest
                                                suggestedRequest:toRequest
                                                   chosenRequest:toRequest
                                                      completion:completionHandler];
        }
    });
}

- (void)_network_willPerformHTTPRedirectionFromRequest:(NSURLRequest *)fromRequest
                                              response:(NSHTTPURLResponse *)response
                                       originalRequest:(NSURLRequest *)originalRequest
                                      suggestedRequest:(NSURLRequest *)suggestedRequest
                                         chosenRequest:(nullable id<TNLRequest>)chosenRequest
                                            completion:(void(^)(NSURLRequest * __nullable))completionHandler
{
    NSURLRequest *toRequest = nil;
    if (chosenRequest) {
        if (chosenRequest == suggestedRequest) {
            toRequest = suggestedRequest;
        } else {
            NSError *error = nil;
            toRequest = TNLRequestToNSURLRequest(chosenRequest, nil /*config*/, &error);
            if (!toRequest) {
                TNLLogError(@"Provided TNLHTTPRequest (%@) for redirect cannot be converted into an NSURLRequest! %@", chosenRequest, error);
            }
        }
    }

    [self _network_handleRedirectFromRequest:fromRequest
                                    response:response
                                   toRequest:toRequest
                                  completion:completionHandler];
}

- (void)_network_handleRedirectFromRequest:(NSURLRequest *)fromRequest
                                  response:(NSHTTPURLResponse *)response
                                 toRequest:(nullable NSURLRequest *)toRequest
                                completion:(void(^)(NSURLRequest * __nullable))completionHandler
{

    TNLRequestOperation *requestOperation = _requestOperation;
    void (^block)(NSURLRequest * __nullable, NSError * __nullable);
    block = ^void(NSURLRequest * __nullable sanitizedRequest, NSError * __nullable sanitiziationError) {

        TNLAssertIsNetworkQueue();
        NSURLRequest *finalToRequest = (sanitiziationError) ? nil : [sanitizedRequest copy];

        if (!finalToRequest) {

            // IDYN-419
            //
            // Traditionally (and per Apple docs), we should be able to just
            // call the completionHandler with nil.  However, due to a bug in
            // the NSURL framework, doing so when a custom NSURLProtocol is in
            // use will result in the session task becoming impotent and
            // hanging until the operation times out.
            //
            // As a workaround, we will cache the response since the task
            // won't be retaining the response as a property, and cancel the
            // task ourselves.  Our task completion callback will handle the
            // cancellation noting the cached response permitting us to simulate
            // the behavior we would expect.

            self->_cancelledRedirectResponse = response;
            [self.URLSessionTask cancel]; // will trigger the completion callback
            return;
        } else {
            // associate the request config with the new request we redirected to
            TNLRequestConfigurationAssociateWithRequest(self.requestConfiguration, finalToRequest);
        }

        completionHandler(finalToRequest);

        if (sanitiziationError) {
            [self _network_fail:sanitiziationError];
            return;
        } else if (self.isComplete || self.finalizing) {
            return;
        } else if ([self _network_shouldCancel]) {
            [self _network_cancel];
            return;
        }

        if (self->_flags.useIdleTimeoutForInitialConnection) {
            // only restart if we want the idle timer to also be for connection time
            [self _network_restartIdleTimer];
        }

        [self _network_transitionToState:TNLRequestOperationStateRunning];
        TNLAttemptMetaData *metadata = [self network_metaDataWithLowerCaseHeaderFields:[response.allHeaderFields tnl_copyWithLowercaseKeys]];
        [requestOperation network_URLSessionTaskOperation:self
                                           redirectedFrom:fromRequest
                                         withHTTPResponse:response
                                                       to:finalToRequest
                                                 metaData:metadata];
    };

    if (toRequest && requestOperation) {
        [requestOperation network_URLSessionTaskOperation:self
                                      redirectFromRequest:fromRequest
                                         withHTTPResponse:response
                                                       to:toRequest
                                        completionHandler:block];
    } else {
        block(toRequest, nil);
    }
}

// don't support per request operation auth challenges yet
//- (void)URLSession:(NSURLSession *)session
//        task:(NSURLSessionTask *)task
//        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
//        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
//{
//    [self URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
//}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream * __nullable bodyStream))completionHandler
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{

        if (self->_flags.useIdleTimeoutForInitialConnection) {
            [self _network_restartIdleTimer];
        } else {
            [self _network_stopIdleTimer];
        }

        id<TNLRequest> request = self->_hydratedRequest;
        NSInputStream *stream = nil;
        if ([request respondsToSelector:@selector(HTTPBodyStream)]) {
            stream = request.HTTPBodyStream;
        }
        completionHandler(stream);
    });
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didSendBodyData:(int64_t)bytesSent
        totalBytesSent:(int64_t)totalBytesSent
        totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (self.isComplete || self.finalizing) {
            return;
        } else if ([self _network_shouldCancel]) {
            [self _network_cancel];
            return;
        }

        [self _network_transitionToState:TNLRequestOperationStateRunning];
        const float progress = [self _network_uploadProgress];
        [self _network_updateUploadProgress:progress];
        [self _network_restartIdleTimer];
    });
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didCompleteWithError:(nullable NSError *)theError
{
    TNLAssertMessage(theError != nil || task.response != nil, @"task: %@\n%@", task, task.currentRequest);

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{

        if (!self->_completionCallbackDate && !self->_flags.encounteredCompletionBeforeTaskMetrics) {
            self->_completionCallbackDate = [NSDate date];
        }

        if (!self->_taskMetrics && !self->_flags.encounteredCompletionBeforeTaskMetrics) {
            TNLAssert([NSURLSessionTaskMetrics class] != Nil);

            /*
                 Radar #27098270 - filed with iOS 10 beta 1

                 iOS 10 GM and macOS 10.12 GM released with a bug that the completion callback is
                 called BEFORE the task metrics callback is called.  This directly contradicts the
                 Apple documentation which can be seen clearly in `NSURLSession.h`:

                     // Sent as the last message related to a specific task.  Error may be
                     // nil, which implies that no error occurred and this task is complete.
                     - (void)URLSession:(NSURLSession *)session
                                   task:(NSURLSessionTask *)task
                   didCompleteWithError:(nullable NSError *)error;

                 To work around this issue, we will "cache" the completion and retrigger it once we
                 finally get the task metrics.  As a failsafe, we will set a short timer to force
                 completion even if the task metrics don't come through.
             */

            self->_flags.encounteredCompletionBeforeTaskMetrics = 1;
            self->_cachedCompletionSession = session;
            self->_cachedCompletionTask = task;
            self->_cachedCompletionError = theError;

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTaskMetricsNotSeenOnCompletionDelayCompletionDuration * NSEC_PER_SEC)), tnl_network_queue(), ^{
                @autoreleasepool {
                    [self _network_completeCachedCompletionIfPossible];
                }
            });

            return;
        }

        NSError *error = theError;
        if (self.isComplete || self.finalizing) {
            return;
        } else if ([self _network_shouldCancel]) {
            [self _network_cancel];
            return;
        }

        [self _network_transitionToState:TNLRequestOperationStateRunning];

        [self _network_captureResponseFromTaskIfNeeded:task URLSession:session];

        TNLAssertMessage(task == self.URLSessionTask, @"task[%tu]:%@ != task[%tu]:%@", task.taskIdentifier, task, self.URLSessionTask.taskIdentifier, self.URLSessionTask);
        TNLAssertMessage(error != nil || task.response != nil, @"task: %@\n%@", task, task.currentRequest);

        if (!error && self->_contentDecoderContext) {
            [self _network_stopIdleTimer];
            [self _finishDecodingWithURLSession:session dataTask:(NSURLSessionDataTask *)task];
            return;
        }

        [self _network_finalizeDidCompleteTask:task URLSession:session error:error];
    });
}

- (void)_finishDecodingWithURLSession:(NSURLSession *)completedURLSession
                             dataTask:(NSURLSessionDataTask *)dataTask
{
    tnl_dispatch_async_autoreleasing(tnl_coding_queue(), ^{
        NSError *decodingError = nil;
        if (![self->_contentDecoder tnl_finalizeDecoding:self->_contentDecoderContext error:&decodingError]) {
            decodingError = TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationRequestContentDecodingFailed, decodingError);
        }
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            const BOOL hasRecentData = self->_contentDecoderRecentData.length > 0;
            if (hasRecentData) {
                // flush is synchronous
                [self _network_flushDecoding:decodingError
                                  completion:^(NSData * __nullable decodedData, NSError * __nullable flushDecodingError) {
                    [self _network_didDecodeData:decodedData
                                      URLSession:completedURLSession
                                        dataTask:dataTask
                                           error:flushDecodingError];
                }];
            }
            // error would be triggered in the flush which would yield the op to fail before this point
            [self _network_finalizeDidCompleteTask:dataTask
                                        URLSession:completedURLSession
                                             error:nil];
        });
    });
}

- (void)_network_finalizeDidCompleteTask:(NSURLSessionTask *)task
                              URLSession:(NSURLSession *)session
                                   error:(nullable NSError *)error
{
    if (self.isComplete || self.finalizing) {
        return;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return;
    }

    _contentDecoderContext = nil;
    _contentDecoderRecentData = nil;
    [self _network_stopIdleTimer];

    BOOL success = YES;
    if (error) {
        success = NO;
        if ([error.domain isEqualToString:NSURLErrorDomain]) {
            switch (error.code) {
                case NSURLErrorCancelled:
                {
                    if (_flags.didCancel) {
                        // cancel, not an error
                        error = nil;
                        if (_cancelledRedirectResponse) {
                            success = YES;
                        }
                    } else {

                        // other cancellation

                        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
                        if (_authChallengeCancelledUserInfo) {
                            // definitely auth challenge
                            [userInfo addEntriesFromDictionary:self->_authChallengeCancelledUserInfo];
                        } else {
                            // unknown, but treat as auth challenge anyway
                        }

                        userInfo[NSUnderlyingErrorKey] = error;
                        error = TNLErrorCreateWithCodeAndUserInfo(TNLErrorCodeRequestOperationAuthenticationChallengeCancelled, userInfo);

                    }
                    break;
                }
                case NSURLErrorBadServerResponse:
                {
                    // Log the error
                    TNLLogError(@"TNLURLSessionTaskOperation completed with bad server response error! %@", error);
                    break;
                }
                case NSURLErrorTimedOut:
                {
                    // Replace the generic NSURL timeout with the specific TNL timeout
                    error = TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationAttemptTimedOut, error);
                    break;
                }
                default:
                    break;
            }
        }
    }

    if (success) {
        [self _network_complete];
    } else {
        if (error) {
            [self _network_fail:error];
        } else {
            [self _network_cancel];
        }
    }
}

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        self->_taskMetricsCallbackDate = [NSDate date];
        self->_taskMetrics = metrics;

        /*
            Radar #27098270 - filed with iOS 10 beta 1

            iOS 10 GM and macOS 10.12 GM released with a bug that the completion callback is
            called BEFORE the task metrics callback is called.  This directly contradicts the
            Apple documentation which can be seen clearly in `NSURLSession.h`:

                // Sent as the last message related to a specific task.  Error may be
                // nil, which implies that no error occurred and this task is complete.
                - (void)URLSession:(NSURLSession *)session
                              task:(NSURLSessionTask *)task
              didCompleteWithError:(nullable NSError *)error;

            To work around this issue, we will "cache" the completion and retrigger it once we
            finally get the task metrics.  As a failsafe, we will set a short timer to force
            completion even if the task metrics don't come through.
         */

        [self _network_completeCachedCompletionIfPossible];
    });
}

#pragma mark NSURLSessionDataTaskDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_didReceiveResponse:response URLSession:session task:dataTask];
        completionHandler(NSURLSessionResponseAllow);
    });
}

// Not implemented a.t.m.
/*
- (void)URLSession:(NSURLSession *)session
        dataTask:(NSURLSessionDataTask *)dataTask
        didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask
 */

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    // callback called on bg queue
    [self _decodeData:data
           completion:^(NSData * __nullable decodedData, NSError * __nullable decodeError) {
        [self _network_didDecodeData:decodedData
                          URLSession:session
                            dataTask:dataTask
                               error:decodeError];
    }];
}

- (void)_network_didDecodeData:(nullable NSData *)decodedData
                    URLSession:(NSURLSession *)session
                      dataTask:(NSURLSessionDataTask *)dataTask
                         error:(nullable NSError *)decodeError
{
    if (self.isComplete || self.isFinalizing) {
        return;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return;
    }

    [self _network_captureResponseFromTaskIfNeeded:dataTask URLSession:session];
    NSError *error = decodeError ?: [self _network_appendDecodedData:decodedData];
    if (error) {
        [self _network_fail:error];
    } else {
        [self _network_updateDownloadProgress:[self _network_downloadProgress]];
        [self _network_restartIdleTimer];
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
    // TODO:[nobrien] - expose this via one of the request delegates or configuration (NSURLCacheStoragePolicy)
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_restartIdleTimer];
        completionHandler(proposedResponse);
    });
}

#pragma mark NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
        downloadTask:(NSURLSessionDownloadTask *)downloadTask
        didFinishDownloadingToURL:(NSURL *)location
{
    // Capture the temp file immediately
    NSError *error;
    TNLTemporaryFile *tempFile = [TNLTemporaryFile temporaryFileWithExistingFilePath:location.path
                                                                               error:&error];
    TNLAssert(tempFile != nil || error != nil);

    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        self->_tempFile = tempFile;
        if (!self->_tempFile) {
            [self _network_fail:error];
        } else {
            [self _network_captureResponseFromTaskIfNeeded:downloadTask URLSession:session];
            [self _network_restartIdleTimer];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
        downloadTask:(NSURLSessionDownloadTask *)downloadTask
        didWriteData:(int64_t)bytesWritten
        totalBytesWritten:(int64_t)totalBytesWritten
        totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_didUpdateTotalBytesReceived:totalBytesWritten
                                     expectedBytes:totalBytesExpectedToWrite
                                        URLSession:session
                                      downloadTask:downloadTask];
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        [self _network_didUpdateTotalBytesReceived:fileOffset
                                     expectedBytes:expectedTotalBytes
                                        URLSession:session
                                      downloadTask:downloadTask];
    });
}

#pragma mark - Decoding

- (void)_decodeData:(NSData *)data
         completion:(void(^)(NSData * __nullable decodedData, NSError * __nullable decodeError))completion
{
    if (!_contentDecoderContext) {
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            completion(data, nil);
        });
        return;
    }

    const uint64_t decodeStartMachTime = mach_absolute_time();
    tnl_dispatch_async_autoreleasing(tnl_coding_queue(), ^{
        NSError *error = nil;
        const BOOL decodeSuccess = [self->_contentDecoder tnl_decode:self->_contentDecoderContext
                                                      additionalData:data
                                                               error:&error];
        if (!decodeSuccess) {
            error = TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationRequestContentDecodingFailed, error);
        }
        tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
            const NSTimeInterval decodeLatency = TNLComputeDuration(decodeStartMachTime, mach_absolute_time());
            self->_responseDecodeLatency += decodeLatency;
            [self _network_flushDecoding:error completion:completion];
        });
    });
}

- (void)_network_flushDecoding:(nullable NSError *)error
                    completion:(void(^)(NSData * __nullable decodedData, NSError * __nullable decodeError))completion
{
    if (error) {
        _contentDecoderContext = nil;
        _contentDecoderRecentData = nil;
        completion(nil, error);
    } else {
        // flush the recent data
        NSData *recentData = _contentDecoderRecentData;
        _contentDecoderRecentData = nil;
        completion(recentData, nil);
    }
}

- (BOOL)tnl_dataWasDecoded:(NSData *)data error:(out NSError **)error
{
    tnl_dispatch_async_autoreleasing(tnl_network_queue(), ^{
        if (!self->_contentDecoderRecentData) {
            self->_contentDecoderRecentData = [data mutableCopy];
        } else {
            [self->_contentDecoderRecentData appendData:data];
        }
    });
    if (error) {
        *error = nil;
    }
    return YES; // defer the error to the append data handler
}

@end

#pragma mark - TNLURLSessionTaskOperation (Network)

@implementation TNLURLSessionTaskOperation (Network)

#pragma mark Properties

- (TNLAttemptMetaData *)network_metaDataWithLowerCaseHeaderFields:(nullable NSDictionary *)lowerCaseHeaderFields
{
    NSURLSessionTask *task = self.URLSessionTask;
    TNLAttemptMetaData *metaData = [[TNLAttemptMetaData alloc] init];
    metaData.HTTPVersion = @"1.1";
    metaData.sessionId = _URLSession.sessionDescription;

    if (task) {

        NSHTTPURLResponse *response = self.URLResponse;
        TNLAssert(!response || response == task.response || response == _cancelledRedirectResponse);

        metaData.responseLowercaseHeaders = lowerCaseHeaderFields;

        if (_layer8BodyBytesReceived >= 0) {
            metaData.layer8BodyBytesReceived = _layer8BodyBytesReceived;
        }
        if (task.countOfBytesSent >= 0) {
            metaData.layer8BodyBytesTransmitted = task.countOfBytesSent;
        }
        if (task.countOfBytesExpectedToSend >= 0) {
            metaData.requestContentLength = task.countOfBytesExpectedToSend;
        }

        const long long contentLength = [response tnl_expectedResponseBodySize];
        if (contentLength >= 0) {
            metaData.responseContentLength = contentLength;
        } else if (task.countOfBytesExpectedToReceive >= 0) {
            metaData.responseContentLength = task.countOfBytesExpectedToReceive;
        }

        NSString *responseTime = lowerCaseHeaderFields[@"x-response-time"];
        if (responseTime) {
            metaData.serverResponseTime = [responseTime longLongValue];
        }

        if (_hashData) {
            metaData.responseBodyHashAlgorithm = _hashAlgo;
            metaData.responseBodyHash = _hashData;
        }

        metaData.localCacheHit = response.tnl_wasCachedResponse;

        if (_responseBodyEndDate && _responseBodyStartDate) {
            metaData.responseContentDownloadDuration = [_responseBodyEndDate timeIntervalSinceDate:_responseBodyStartDate];
        }

        if (_responseDecodeLatency > 0) {
            metaData.responseDecodingLatency = _responseDecodeLatency;
        }
        if (_layer8BodyBytesReceived > 0) {
            metaData.responseDecodedContentLength = _layer8BodyBytesReceived;
        }

        if (_taskResumeDate) {
            // indicates we also have task resume priority
            metaData.taskResumePriority = _taskResumePriority;
        }

        if (_taskMetrics && _taskResumeDate) {
            const NSTimeInterval fetchResumeDelta = [_taskMetrics.transactionMetrics.firstObject.fetchStartDate timeIntervalSinceDate:_taskResumeDate];
            if (fetchResumeDelta > 1.0 || fetchResumeDelta < -1.0) {
                metaData.taskResumeLatency = fetchResumeDelta;
            }
        }

        if (_completionCallbackDate) {
            // we were going to capture task metrics, see if there's any discrepency
            if (_taskMetricsCallbackDate) {
                const NSTimeInterval taskMetricsLatency = [_taskMetricsCallbackDate timeIntervalSinceDate:_completionCallbackDate];
                if (taskMetricsLatency > 0.0) {
                    // should not get task metrics after completion!
                    metaData.taskMetricsAfterCompletionLatency = taskMetricsLatency;
                }
            } else {
                NSDate *dateNow = [NSDate date];
                const NSTimeInterval latencySinceCompletion = [dateNow timeIntervalSinceDate:_completionCallbackDate];
                if (latencySinceCompletion >= 0.100) {
                    // should really be no latency, so capture any meaningful latency
                    metaData.taskWithoutMetricsCompletionLatency = latencySinceCompletion;
                }
            }
        }
    }

    return metaData;
}

- (nullable NSURLSessionTaskMetrics *)network_taskMetrics
{
    return _taskMetrics;
}

- (float)_network_uploadProgress
{
    const int64_t bytesToSend = self.URLSessionTask.countOfBytesExpectedToSend;
    const int64_t bytesSent = self.URLSessionTask.countOfBytesSent;
    NSURLResponse *response = self.URLResponse;

    if (TNLRequestOperationStateSucceeded == atomic_load(&_internalState) || response != nil) {
        return 1.0f;
    } else if (bytesToSend <= 0) {
        // Non-deterministic
        return 0.0f;
    }

    const double doubleProgress = (double)bytesSent / (double)(bytesToSend);
    // progress can be > 1.0 if bytesSent is > bytesToSend
    return (float)doubleProgress;
}

- (float)_network_downloadProgress
{
    const int64_t bytesToReceive = self.URLSessionTask.countOfBytesExpectedToReceive;
    const int64_t bytesReceived = self.URLSessionTask.countOfBytesReceived;
    NSHTTPURLResponse *response = self.URLResponse;
    if (nil != [response tnl_contentEncoding]) {
        // Non-deterministic
        return 0.0f;
    }

    if (TNLRequestOperationStateSucceeded == atomic_load(&_internalState)) {
        return 1.0f;
    } else if (bytesToReceive <= 0) {
        // Non-deterministic
        return 0.0f;
    }

    const double doubleProgress = (double)(bytesReceived) / (double)(bytesToReceive);
    // progress can be > 1.0 if bytesReceived is > bytesToReceive
    return (float)doubleProgress;
}

#pragma mark NSOperation

- (BOOL)_network_shouldCancel
{
    if (TNLRequestOperationStateIsFinal(atomic_load(&_internalState))) {
        return NO;
    }

    TNLRequestOperation *requestOperation = _requestOperation;
    if (requestOperation != nil) {
        return NO;
    }

    if ([_error.domain isEqualToString:TNLErrorDomain] && _error.code == TNLErrorCodeRequestOperationCancelled) {
        // Already cancelling
        return NO;
    }

    if (_requestConfiguration.URLCache != nil) {
        // Has a cache, should we permit it to finish?

        // TODO:[nobrien] - use better heuristics here

        if ([self _currentRequestHasBody]) {
            return [self _network_uploadProgress] < 0.9;
        } else {
            return [self _network_downloadProgress] < 0.9;
        }
    }

    return YES;
}

#pragma mark Methods

- (void)_network_willResumeSessionTaskWithRequest:(NSURLRequest *)resumeRequest
{
    [_requestOperation network_URLSessionTaskOperation:self
                        didStartSessionTaskWithRequest:resumeRequest];
}

- (void)_network_resumeSessionTask:(NSURLSessionTask *)task
{
    // NSURLSessionTask's `resume` will capture the QOS of the calling queue for
    // reusing the same QOS for the execution of the task

    const TNLPriority requestPriority = self.requestPriority;
    dispatch_sync(dispatch_get_global_queue((long)TNLConvertTNLPriorityToGCDQOS(requestPriority), 0), ^{
        self->_taskResumeDate = [NSDate date];
        self->_taskResumePriority = requestPriority;
        [task resume];
    });
}

- (void)_network_didStartTask:(BOOL)isBackgroundRequest
{
    NSUInteger taskId = self.URLSessionTask.taskIdentifier;
    NSString *configId = _URLSession.configuration.identifier;
    NSString *sharedContainerIdentifier = _URLSession.configuration.sharedContainerIdentifier;

    [_requestOperation network_URLSessionTaskOperation:self
                        didStartTaskWithTaskIdentifier:taskId
                                      configIdentifier:configId
                             sharedContainerIdentifier:sharedContainerIdentifier
                                   isBackgroundRequest:isBackgroundRequest];
}

- (void)_network_updatePriorities
{
    TNLPriority pri = TNLPriorityVeryLow;
    TNLRequestOperation *strongRequestOp = _requestOperation;
    if (strongRequestOp) {
        TNLPriority opPri = strongRequestOp.priority;
        if (opPri > pri) {
            pri = opPri;
        }
    }
    _requestPriority = pri;
    self.URLSessionTask.priority = TNLConvertTNLPriorityToURLSessionTaskPriority(self->_requestPriority);

    // Apple discourages modifying NSOperation properties once an operation has been added to an
    // NSOperationQueue. Crashing has been reproduced when modifying the queuePriority while an
    // NSOperation is executing so we will prevent mutating these priorities if that request has
    // started.
    if (!_requestOperationQueue && !self.isReady) {
        self.queuePriority = TNLConvertTNLPriorityToQueuePriority(self->_requestPriority);
        self.qualityOfService = TNLConvertTNLPriorityToQualityOfService(self->_requestPriority);
    }
}

- (void)_network_buildResponseInfo
{
    if (!_responseInfo) {
        _responseInfo = [[TNLResponseInfo alloc] initWithFinalURLRequest:self.currentURLRequest
                                                             URLResponse:self.URLResponse
                                                                  source:self.responseSource
                                                                    data:_storedData
                                                      temporarySavedFile:_tempFile];
    }
}

- (void)_network_buildInternalResponse
{
    TNLAttemptMetaData *metadata = [self network_metaDataWithLowerCaseHeaderFields:_responseInfo.allHTTPHeaderFieldsWithLowerCaseKeys];
    TNLAttemptMetrics *attemptMetrics = [[TNLAttemptMetrics alloc] initWithType:TNLAttemptTypeInitial
                                                                      startDate:_startDate
                                                                  startMachTime:_startMachTime
                                                                        endDate:_endDate
                                                                    endMachTime:_endMachTime
                                                                       metaData:metadata
                                                                     URLRequest:self.currentURLRequest
                                                                    URLResponse:self.URLResponse
                                                                 operationError:self.error];
    TNLResponseMetrics *metrics = [[TNLResponseMetrics alloc] initWithEnqueueDate:_startDate
                                                                      enqueueTime:_startMachTime
                                                                     completeDate:_completeDate
                                                                     completeTime:_completeMachTime
                                                                   attemptMetrics:@[attemptMetrics]];
    TNLResponse *response = [_responseClass responseWithRequest:self.originalRequest
                                                 operationError:_error
                                                           info:_responseInfo
                                                        metrics:metrics];
    _finalResponse = response;
}

- (void)_network_fail:(NSError *)error
{
    if (self.isComplete || self.isFinalizing) {
        return;
    }

    TNLAssert(error != nil);
    _flags.shouldCaptureResponse = 0; // don't handle responses anymore

    _contentDecoderContext = nil; // don't decode anymore
    _contentDecoderRecentData = nil;

    if (!_flags.didStart) {
        _cachedFailure = error;
        return;
    }

    const BOOL didCancel = [error.domain isEqualToString:TNLErrorDomain] && (error.code == TNLErrorCodeRequestOperationCancelled);
    _flags.didCancel = didCancel;

    // don't use network_cancel
    [self.URLSessionTask cancel];
    [self _network_stopIdleTimer];

    _error = error;
    TNLLogDebug(@"%@ error: %@", self, _error);

    [self _network_finishHashWithSuccess:NO];
    [self _network_buildResponseInfo];
    TNLAssert(_responseInfo);
    [self _network_finalizeWithState:(didCancel) ? TNLRequestOperationStateCancelled : TNLRequestOperationStateFailed];

    // discard temporary file at the end (if needed)
    if (_flags.shouldDeleteUploadFile) {
        [[NSFileManager defaultManager] removeItemAtPath:_uploadFilePath error:NULL];
        _flags.shouldDeleteUploadFile = NO;
    }
}

- (void)_network_cancel
{
    TNLAssert(!_flags.didCancel);
    [self _network_fail:TNLErrorCreateWithCode(TNLErrorCodeRequestOperationCancelled)];
}

- (void)_network_complete
{
    if (self.isComplete || self.isFinalizing) {
        return;
    }

    _flags.shouldCaptureResponse = 0; // don't handle responses anymore
    _contentDecoderContext = nil; // don't decode anymore
    _contentDecoderRecentData = nil;
    _responseBodyEndDate = [NSDate date];

    [self _network_finishHashWithSuccess:YES];
    [self _network_buildResponseInfo];
    TNLAssert(_responseInfo);
    [self _network_finalizeWithState:TNLRequestOperationStateSucceeded];
}

- (void)_network_completeCachedCompletionIfPossible
{
    if (_flags.encounteredCompletionBeforeTaskMetrics) {
        NSURLSession *session = _cachedCompletionSession;
        if (session) {
            NSURLSessionTask *task = _cachedCompletionTask;
            NSError *error = _cachedCompletionError;

            _cachedCompletionSession = nil;
            _cachedCompletionTask = nil;
            _cachedCompletionError = nil;

            [self URLSession:session task:task didCompleteWithError:error];
        } // else, already completed
    }
}

- (void)_network_captureResponseFromTaskIfNeeded:(NSURLSessionTask *)task
                                      URLSession:(NSURLSession *)session
{
    if (_flags.shouldCaptureResponse && task) {
        NSURLResponse *response = task.response;
        if (response) {
            [self _network_didReceiveResponse:response URLSession:session task:task];
        }
    }
}

- (void)_network_didReceiveResponse:(NSURLResponse *)response
                         URLSession:(NSURLSession *)session
                               task:(NSURLSessionTask *)task
{
    if (self.isComplete || self.isFinalizing) {
        return;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return;
    }

    [self _network_transitionToState:TNLRequestOperationStateRunning];

    TNLAssertMessage([response isKindOfClass:[NSHTTPURLResponse class]], @"%@ is not an 'NSHTTPURLResponse'", response);
    TNLAssert(task.response == self.URLResponse);
    if (gTwitterNetworkLayerAssertEnabled) {
        // instances might not match, ensure contents match
        NSHTTPURLResponse *taskResponse = (NSHTTPURLResponse *)task.response;
        TNLAssert([taskResponse.URL isEqual:response.URL]);
        TNLAssert(taskResponse.allHeaderFields.count == [(NSHTTPURLResponse *)response allHeaderFields].count);
        TNLAssert(taskResponse.statusCode == [(NSHTTPURLResponse *)response statusCode]);
    }

    NSError *decodingError = nil;
    NSString *acceptEncoding = [[(NSHTTPURLResponse *)response allHeaderFields] tnl_objectForCaseInsensitiveKey:@"Content-Encoding"];
    if (acceptEncoding) {
        acceptEncoding = [acceptEncoding lowercaseString];
        _contentDecoder = self->_additionalDecoders[acceptEncoding];
        if (_contentDecoder) {
            _contentDecoderContext = [_contentDecoder tnl_initializeDecodingWithContentEncoding:acceptEncoding
                                                                                         client:self
                                                                                          error:&decodingError];
        }
    }

    _flags.shouldCaptureResponse = 0;

    _responseBodyStartDate = [NSDate date];
    [self _network_updateUploadProgress:[self _network_uploadProgress]];
    [self _network_updateDownloadProgress:[self _network_downloadProgress]];
    [_requestOperation network_URLSessionTaskOperation:self
                                 didReceiveURLResponse:response];

    if (decodingError) {
        [self _network_fail:TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCodeRequestOperationRequestContentDecodingFailed, decodingError)];
        return;
    }
    [self _network_restartIdleTimer];
}

- (void)_network_didUpdateTotalBytesReceived:(int64_t)bytesReceived
                               expectedBytes:(int64_t)totalBytesExpectedToReceive
                                  URLSession:(NSURLSession *)session
                                downloadTask:(NSURLSessionDownloadTask *)downloadTask
{
    if (self.isComplete || self.isFinalizing) {
        return;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return;
    }

    [self _network_transitionToState:TNLRequestOperationStateRunning];

    TNLAssert([[downloadTask response] isKindOfClass:[NSHTTPURLResponse class]]);
    TNLAssert(downloadTask.response != nil);

    [self _network_captureResponseFromTaskIfNeeded:downloadTask URLSession:session];
    [self _network_updateDownloadProgress:[self _network_downloadProgress]];
    [self _network_restartIdleTimer];
}

- (void)_network_updateUploadProgress:(float)progress
{
    if (self.isComplete) {
        return;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return;
    }

    [_requestOperation network_URLSessionTaskOperation:self
                               didUpdateUploadProgress:progress];
}

- (void)_network_updateDownloadProgress:(float)progress
{
    if (self.isComplete) {
        return;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return;
    }

    [_requestOperation network_URLSessionTaskOperation:self
                             didUpdateDownloadProgress:progress];
}

- (nullable NSError *)_network_appendDecodedData:(nullable NSData *)data
{
    if (self.isComplete || self.isFinalizing) {
        return nil;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return nil;
    }

    NSError *error = nil;
    [self _network_transitionToState:TNLRequestOperationStateRunning];
    [self _network_updateHashWithData:data];

    NSHTTPURLResponse *URLResponse = self.URLResponse;

    _layer8BodyBytesReceived += data.length;

    switch (_requestConfiguration.responseDataConsumptionMode) {
        case TNLResponseDataConsumptionModeNone:
            break;
        case TNLResponseDataConsumptionModeStoreInMemory:

            @try {
                if (!_storedData) {
                    // We want the buffer of the mutable data to be the best guess we can offer to
                    // prevent continuous reallocs.
                    NSUInteger capacity = 0;
                    long long expectedDataSize = [URLResponse tnl_expectedResponseBodyExpandedDataSize];

                    // NOTE - it is possible that the expectedDataSize is the Content-Length which
                    // is the compressed size so it will be too small for the decompressed size.
                    // However, we know that the content will be at least as much as the
                    // Content-Length when decompressed so setting the capacity to the
                    // Content-Length will avoid the initial reallocs, but will still incur later
                    // reallocs so it is no worse than not setting the capacity.

                    if (expectedDataSize >= (LONG_MAX - EXTRA_DOWNLOAD_BYTES_BUFFER)) {
                        capacity = LONG_MAX;
                    } else if (expectedDataSize > 0) {
                        capacity = (NSUInteger)expectedDataSize + EXTRA_DOWNLOAD_BYTES_BUFFER;
                    }
                    _storedData = (capacity > 0) ? [NSMutableData dataWithCapacity:capacity] : [NSMutableData data];
                }
                if (data) {
                    [_storedData appendData:data];
                }
            } @catch (NSException *exception) {
                TNLLogError(@"Append Data Exception: %@", exception);
                error = TNLErrorCreateWithCodeAndUserInfo(TNLErrorCodeRequestOperationAppendResponseDataError,
                                                          @{ @"exception" : exception });
                _storedData = nil;
            }
            break;
        case TNLResponseDataConsumptionModeSaveToDisk:
            TNLAssertNever(); // should be a download task
            break;
        case TNLResponseDataConsumptionModeChunkToDelegateCallback:
            if (data) {
                [_requestOperation network_URLSessionTaskOperation:self appendReceivedData:data];
            }
            break;
    }

    return error;
}

- (void)_network_finalizeWithState:(TNLRequestOperationState)state
{
    [self _network_finalizeWithResponseCompletion:^(TNLResponse * __nullable finalResponse) {
        TNLAssertIsNetworkQueue();
        if (finalResponse) {
            self->_finalResponse = finalResponse;
        }
        if (!self->_finalResponse) {
            [self _network_buildInternalResponse];
        }
        TNLAssert(self->_finalResponse);
        self->_responseInfo = self->_finalResponse.info;
        [self _network_transitionToState:state];
        self->_flags.isFinalizing = NO;
    }];
}

- (void)_network_finalizeWithResponseCompletion:(TNLRequestMakeFinalResponseCompletionBlock)completion
{
    if (self.isComplete || self.isFinalizing) {
        return;
    } else if ([self _network_shouldCancel]) {
        [self _network_cancel];
        return;
    }

    _flags.isFinalizing = YES;
    _endMachTime = mach_absolute_time();
    _endDate = [NSDate date];

    TNLRequestOperation *strongRequestOp = _requestOperation;
    if (strongRequestOp) {
        NSURLSessionTaskMetrics *taskMetrics = _taskMetrics;

        TNLAttemptMetaData *metaData = [self network_metaDataWithLowerCaseHeaderFields:_responseInfo.allHTTPHeaderFieldsWithLowerCaseKeys];
        [strongRequestOp network_URLSessionTaskOperation:self
                                finalizeWithResponseInfo:_responseInfo
                                           responseError:_error
                                                metaData:metaData
                                             taskMetrics:taskMetrics
                                              completion:completion];
    } else {
        completion(nil);
    }
}

- (void)_network_transitionToState:(TNLRequestOperationState)state
{
    if (self.isComplete) {
        return;
    } else if (self.isFinalizing) {
        TNLAssert(TNLRequestOperationStateIsFinal(state));
    } else if ([self _network_shouldCancel]) {
        // If we are finalizing or moving to be completed, no need to pre-emtively cancel
        if (!TNLRequestOperationStateIsFinal(state)) {
            [self _network_cancel];
            return;
        }
    }

    TNLRequestOperationState oldState = atomic_load(&_internalState);
    if (oldState != state) {
        if (TNLRequestOperationStateRunning == state && TNLRequestOperationStateStarting != oldState) {
            return;
        }

        if (gTwitterNetworkLayerAssertEnabled) {
            switch (state) {
                case TNLRequestOperationStateIdle:
                case TNLRequestOperationStatePreparingRequest:
                case TNLRequestOperationStateWaitingToRetry:
                    TNLAssertNever();
                    break;
                case TNLRequestOperationStateStarting:
                case TNLRequestOperationStateRunning:
                    TNLAssertMessage(oldState < state, @"oldState (%ld) < newState (%ld)", (long)oldState, (long)state);
                    break;
                case TNLRequestOperationStateCancelled:
                case TNLRequestOperationStateFailed:
                case TNLRequestOperationStateSucceeded:
                    TNLAssert(!TNLRequestOperationStateIsFinal(oldState));
                    TNLAssert(_finalResponse != nil);
                    break;
            }
        }

        // KVO - Prep

        TNLRequestOperation *strongRequestOp = _requestOperation;

        BOOL cancelDidChange = NO;
        BOOL finishedDidChange = NO;
        BOOL executingDidChange = NO;
        if (TNLRequestOperationStateIsFinal(state)) {
            cancelDidChange = (TNLRequestOperationStateCancelled == state);
            finishedDidChange = YES;
            executingDidChange = YES;
        } else if (TNLRequestOperationStateIdle == oldState) {
            executingDidChange = YES;
        }

        // Will transition logic

        if (finishedDidChange) {

            // will transition to isFinished

            // validate "didStart" flag
            if (!_flags.didStart) {
                TNLLogError(@"%@ changed stated to be final before being started!\n%@", NSStringFromClass([self class]), self.originalURLRequest);
            }
            TNLAssert(_flags.didStart);

            // stop handling responses
            _flags.shouldCaptureResponse = 0;

            // check for backoff signal
            TNLResponseInfo *info = _finalResponse.info;
            const TNLHTTPStatusCode statusCode = info.statusCode;
            NSDictionary *headers = info.allHTTPHeaderFieldsWithLowerCaseKeys;
            NSString *host = nil;
            NSURL *URL = _hydratedURLRequest.URL;
            if ([TNLGlobalConfiguration sharedInstance].shouldBackoffUseOriginalRequestHost) {
                host = [_originalRequest URL].host;
            }
            const BOOL shouldSignal = [[TNLGlobalConfiguration sharedInstance].backoffSignaler tnl_shouldSignalBackoffForURL:URL
                                                                                                                        host:host
                                                                                                                  statusCode:statusCode
                                                                                                             responseHeaders:headers];
            if (shouldSignal) {
                [TNLNetwork backoffSignalEncounteredForURL:URL
                                                      host:host
                                       responseHTTPHeaders:headers];
            }
        }

        if (executingDidChange) {
            if (TNLRequestOperationStateIdle == oldState && !finishedDidChange) {

                // will transition to isExecuting

                if (!_flags.didIncrementExecutionCount && _requestConfiguration.contributeToExecutingNetworkConnectionsCount) {
                    _flags.didIncrementExecutionCount = YES;
                    [TNLNetwork incrementExecutingNetworkConnections];
                }

            }
        }

        // Timestamps

        [self _network_updateTimestampsWithState:state];

        // KVO - transition

        if (finishedDidChange) {
            [self willChangeValueForKey:@"isFinished"];
        }
        if (cancelDidChange) {
            [self willChangeValueForKey:@"isCancelled"];
        }
        if (executingDidChange) {
            [self willChangeValueForKey:@"isExecuting"];
        }

        atomic_store(&_internalState, state);
        if (finishedDidChange) {
            // Last chance to update progress
            [strongRequestOp network_URLSessionTaskOperation:self
                                     didUpdateUploadProgress:[self _network_uploadProgress]];
            [strongRequestOp network_URLSessionTaskOperation:self
                                   didUpdateDownloadProgress:[self _network_downloadProgress]];
        }
        [strongRequestOp network_URLSessionTaskOperation:self
                                    didTransitionToState:state
                                            withResponse:_finalResponse];

        if (executingDidChange) {
            [self didChangeValueForKey:@"isExecuting"];
        }
        if (cancelDidChange) {
            [self didChangeValueForKey:@"isCancelled"];
        }
        if (finishedDidChange) {
            [self didChangeValueForKey:@"isFinished"];
        }

        // Log transition

        TNLLogDebug(@"%@: %@ -> %@", self, TNLRequestOperationStateToString(oldState), TNLRequestOperationStateToString(state));

        // Did transition logic

        if (finishedDidChange) {

            // Did transition to isFinished

            // Decrement execution count
            if (_flags.didIncrementExecutionCount) {
                [TNLNetwork decrementExecutingNetworkConnections];
                _flags.didIncrementExecutionCount = NO;
            }

            // Anonymous completion
            if (!strongRequestOp) {
                [self.requestOperationQueue taskOperation:self
                                       didCompleteAttempt:_finalResponse];
            }

        }

        // Background Completion

        if (finishedDidChange && _executionMode == TNLRequestExecutionModeBackground && (_downloadTask != nil || _uploadTask != nil)) {
            NSString *sharedContainerIdentifier = _URLSession.configuration.sharedContainerIdentifier;
            TNLAssert(_finalResponse);
            [_sessionManager URLSessionDidCompleteBackgroundTask:self.URLSessionTask.taskIdentifier
                                         sessionConfigIdentifier:_URLSession.configuration.identifier
                                       sharedContainerIdentifier:sharedContainerIdentifier
                                                         request:self.originalURLRequest
                                                        response:_finalResponse];
        }
    }
}

- (void)_network_updateTimestampsWithState:(TNLRequestOperationState)state
{
    if (!_startMachTime) {
        _startDate = [NSDate date];
        _startMachTime = mach_absolute_time();
    }

    if (TNLRequestOperationStateIsFinal(state)) {
        NSDate *dateNow = [NSDate date];
        const uint64_t machTime = mach_absolute_time();
        _completeMachTime = machTime;
        _completeDate = dateNow;
        if (!_endMachTime) {
            _endDate = dateNow;
            _endMachTime = machTime;
        }
        TNLAssert(_finalResponse);
        TNLAssert(_completeMachTime > 0);
        if (!_finalResponse.metrics.completeDate) {
            [_finalResponse.metrics setCompleteDate:_completeDate machTime:_completeMachTime];
        }
    }
}

- (void)_network_createTaskWithRequest:(NSURLRequest *)request
                             prototype:(id<TNLRequest>)requestPrototype
                            completion:(void(^)(NSURLSessionTask *createdTask, NSError *error))complete
{
    TNLAssert(!self.URLSessionTask);
    TNLAssert(request);
    TNLAssert(!self.originalURLRequest);
    TNLAssert(_requestConfiguration);

    NSError *error = nil;
    NSURLSessionTask *task = nil;

    task = [self _network_populateURLSessionTaskWithRequest:request
                                                  prototype:requestPrototype
                                                      error:&error];
    if (!error) {
        _resumeData = nil;
        _taskRequest = request;

        task.priority = TNLConvertTNLPriorityToURLSessionTaskPriority(self->_requestPriority);

        TNLRequestConfigurationAssociateWithRequest(self.requestConfiguration, task.originalRequest ?: self->_taskRequest);
    }

    TNLAssert((nil == error) ^ (nil == task));
    complete(task, error);
}

- (nullable NSURLSessionTask *)_network_populateURLSessionTaskWithRequest:(NSURLRequest *)request
                                                                prototype:(id<TNLRequest>)requestPrototype
                                                                    error:(out NSError * __nullable * __nonnull)errorOut
{
    TNLAssert(errorOut != NULL);
    NSError *error = nil;

    const BOOL hasBody = TNLURLRequestHasBody(request, requestPrototype);
    const BOOL isDownload = TNLResponseDataConsumptionModeSaveToDisk == _requestConfiguration.responseDataConsumptionMode;
    const BOOL isBackground = TNLRequestExecutionModeBackground == _requestConfiguration.executionMode;

    @try {
        if (isDownload) {
            if (hasBody) {
                TNLAssertNever(); // should have been caught by TNLRequestValidate(...)
                error = TNLErrorCreateWithCode(TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
            } else {
                // GET can support resume data
                if (_resumeData && TNLHTTPMethodGET == TNLRequestGetHTTPMethodValue(request)) {
                    // resume data is easily invalidated, wrap our task creation in a try/catch so we can fallback to just a normal download task
                    @try {
                        _downloadTask = [_URLSession downloadTaskWithResumeData:_resumeData];
                    } @catch (NSException *exception) {
                        TNLLogWarning(@"%@", exception);
                    }
                }

                if (!_downloadTask) {
                    _downloadTask = [_URLSession downloadTaskWithRequest:request];
                }
            }
        } else {
            if (isBackground) {
                if ([requestPrototype respondsToSelector:@selector(HTTPBodyFilePath)] && requestPrototype.HTTPBodyFilePath) {
                    // OK
                } else if ([request respondsToSelector:@selector(HTTPBody)] && request.HTTPBody) {
                    // OK
                } else {
                    TNLAssertNever(); // should have been caught by TNLRequestValidate(...)
                    error = TNLErrorCreateWithCode(TNLErrorCodeRequestInvalidBackgroundRequest);
                }
            }

            if (hasBody && !error) {
                if (request.HTTPBody) {
                    if (!isBackground) {
                        _uploadData = request.HTTPBody;
                        _uploadTask = [_URLSession uploadTaskWithRequest:request
                                                                fromData:_uploadData];
                    } else {
                        // NSURLSessionUploadTask cannot upload anything other than a file in the background.
                        // Let's help plug that hole by automatically writing the data to a file so
                        // NSURLSessionUploadTask won't fail
                        _uploadFilePath = TNLWriteDataToTemporaryFile(request.HTTPBody);
                        NSURL *uploadFileURL = [NSURL fileURLWithPath:_uploadFilePath isDirectory:NO];
                        _uploadTask = [_URLSession uploadTaskWithRequest:request
                                                                fromFile:uploadFileURL];
                        _flags.shouldDeleteUploadFile = YES;
                    }
                } else if ([requestPrototype respondsToSelector:@selector(HTTPBodyFilePath)] && requestPrototype.HTTPBodyFilePath) {
                    _uploadFilePath = requestPrototype.HTTPBodyFilePath;
                    NSURL *uploadFileURL = [NSURL fileURLWithPath:_uploadFilePath isDirectory:NO];
                    _uploadTask = [_URLSession uploadTaskWithRequest:request
                                                            fromFile:uploadFileURL];
                } else if ([requestPrototype respondsToSelector:@selector(HTTPBodyStream)] && requestPrototype.HTTPBodyStream) {
                    _uploadTask = [_URLSession uploadTaskWithStreamedRequest:request];
                } else {
                    TNLAssertNever(); // where's the body?
                }
            }

            // Not an upload task?
            if (!_uploadTask && !error) {
                if (isBackground) {
                    TNLAssertNever(); // should have been caught by TNLRequestValidate(...)
                    error = TNLErrorCreateWithCode(TNLErrorCodeRequestInvalidBackgroundRequest);
                } else {
                    _dataTask = [_URLSession dataTaskWithRequest:request];
                }
            }
        }
    }
    @catch (NSException *exception) {

        if ([exception.name isEqualToString:NSInternalInconsistencyException]) {
            // rethrow assertion exceptions
            @throw exception;
        }

        // iOS 9 introduced a new exception.
        // It used to be the case that when you created an NSURLSessionTask with an invalidated session
        // you would just get the URLSession:didBecomeInvalidWithError: callback.
        // Now it is possible for an exception to be thrown - so we need to handle it.
        // The exception is an NSGenericException...so not exactly as concrete as a specific error.
        // We'll just handle any exception (except assertion exceptions) and coerse it into an invalidated session error
        // so that our session retry code will kick in.
        TNLLogError(@"Exception creating NSURLSessionTask! %@", exception);
        error = [NSError errorWithDomain:TNLErrorDomain
                                    code:TNLErrorCodeRequestOperationURLSessionInvalidated
                                userInfo:@{ @"exception" : exception }];
    }

    if (!self.URLSessionTask && !error) {
        NSString *reason = @"Underlying NSURLSessionTask was not populated and no error provided";
        TNLAssertMessage(error || self.URLSessionTask, @"%@", reason);
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:reason
                                     userInfo:nil];
    }

    if (error) {
        *errorOut = error;
    }

    return self.URLSessionTask;
}

#pragma mark Timer

- (void)_network_startIdleTimerWithDeferralDuration:(NSTimeInterval)deferral
{
    TNLAssert(!_idleTimer);
    if (_flags.useIdleTimeout && _requestConfiguration.executionMode != TNLRequestExecutionModeBackground) {
        const NSTimeInterval idleTimeout = _requestConfiguration.idleTimeout;
        if (idleTimeout >= MIN_TIMER_INTERVAL) {
            __weak typeof(self) weakSelf = self;
            _idleTimer = tnl_dispatch_timer_create_and_start(tnl_network_queue(), idleTimeout, TIMER_LEEWAY_WITH_FIRE_INTERVAL(MAX(deferral, 0.0) + idleTimeout), NO, ^{
                [weakSelf _network_idleTimerFired];
            });
        }
    }
}

- (void)_network_stopIdleTimer
{
    tnl_dispatch_timer_invalidate(_idleTimer);
    _idleTimer = NULL;
}

- (void)_network_restartIdleTimer
{
    [self _network_stopIdleTimer];
    [self _network_startIdleTimerWithDeferralDuration:0.0];
}

- (void)_network_idleTimerFired
{
    if (_idleTimer) {
        [self _network_stopIdleTimer];
        if (!self.isComplete && !self.isFinalizing) {
            [self _network_fail:TNLErrorCreateWithCode(TNLErrorCodeRequestOperationIdleTimedOut)];
        }
    }
}

#pragma mark Hash

NS_INLINE void* __nullable _mallocAndInitHashContext(TNLResponseHashComputeAlgorithm algo)
{
#define INIT_HASH(hash) ({ \
    contextRef = malloc(sizeof(CC_##hash##_CTX)); \
    CC_##hash##_Init((CC_##hash##_CTX *)contextRef); \
})

    void* contextRef = NULL;
    switch (algo) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD2:
            INIT_HASH(MD2);
#pragma clang diagnostic pop
            break;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD4:
            INIT_HASH(MD4);
#pragma clang diagnostic pop
            break;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD5:
            INIT_HASH(MD5);
#pragma clang diagnostic pop
            break;
        case TNLResponseHashComputeAlgorithmSHA1:
            INIT_HASH(SHA1);
            break;
        case TNLResponseHashComputeAlgorithmSHA256:
            INIT_HASH(SHA256);
            break;
        case TNLResponseHashComputeAlgorithmSHA512:
            INIT_HASH(SHA512);
            break;
        case TNLResponseHashComputeAlgorithmNone:
        default:
            break;
    }

#undef INIT_HASH

    return contextRef;
}

NS_INLINE void _updateHash(TNLResponseHashComputeAlgorithm algo, void * __nullable contextRef, const void *data, CC_LONG len)
{
    if (!contextRef) {
        return;
    }

#define UPDATE_HASH(hash) ({ \
    CC_##hash##_Update((CC_##hash##_CTX *)contextRef, data, len); \
})

    switch (algo) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD2:
            UPDATE_HASH(MD2);
#pragma clang diagnostic pop
            break;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD4:
            UPDATE_HASH(MD4);
#pragma clang diagnostic pop
            break;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD5:
            UPDATE_HASH(MD5);
#pragma clang diagnostic pop
            break;
        case TNLResponseHashComputeAlgorithmSHA1:
            UPDATE_HASH(SHA1);
            break;
        case TNLResponseHashComputeAlgorithmSHA256:
            UPDATE_HASH(SHA256);
            break;
        case TNLResponseHashComputeAlgorithmSHA512:
            UPDATE_HASH(SHA512);
            break;
        case TNLResponseHashComputeAlgorithmNone:
        default:
            break;
    }

#undef UPDATE_HASH

}

NS_INLINE NSData * __nullable _finalizeHash(TNLResponseHashComputeAlgorithm algo, void * __nullable contextRef, BOOL success)
{
    if (!contextRef) {
        return nil;
    }

    unsigned char *hashBuffer = NULL;
    NSData *hashData = nil;

#define FINALIZE_HASH(hash) ({ \
    hashBuffer = (unsigned char *)malloc(CC_##hash##_DIGEST_LENGTH); \
    hashData = [NSData dataWithBytesNoCopy:hashBuffer length:CC_##hash##_DIGEST_LENGTH freeWhenDone:YES]; \
    CC_##hash##_Final(hashBuffer, (CC_##hash##_CTX *)contextRef); \
})

    switch (algo) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD2:
            FINALIZE_HASH(MD2);
#pragma clang diagnostic pop
            break;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD4:
            FINALIZE_HASH(MD4);
#pragma clang diagnostic pop
            break;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case TNLResponseHashComputeAlgorithmMD5:
            FINALIZE_HASH(MD5);
#pragma clang diagnostic pop
            break;
        case TNLResponseHashComputeAlgorithmSHA1:
            FINALIZE_HASH(SHA1);
            break;
        case TNLResponseHashComputeAlgorithmSHA256:
            FINALIZE_HASH(SHA256);
            break;
        case TNLResponseHashComputeAlgorithmSHA512:
            FINALIZE_HASH(SHA512);
            break;
        case TNLResponseHashComputeAlgorithmNone:
        default:
            break;
    }

#undef FINALIZE_HASH

    return (success) ? hashData : nil;
}

- (void)_network_updateHashWithData:(NSData *)data
{
    if (!_flags.isComputingHash && _flags.shouldComputeHash) {
        _hashContextRef = _mallocAndInitHashContext(_hashAlgo);
        _flags.isComputingHash = YES;
    }

    if (_flags.isComputingHash) {
        [data enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
            _updateHash(self->_hashAlgo, self->_hashContextRef, bytes, (CC_LONG)byteRange.length);
        }];
    }
}

- (void)_network_finishHashWithSuccess:(BOOL)success
{
    if (_flags.isComputingHash) {
        if (_hashContextRef) {
            _hashData = _finalizeHash(_hashAlgo, _hashContextRef, success);
            free(_hashContextRef);
            _hashContextRef = NULL;
        }
        _flags.isComputingHash = NO;
    }
}

@end

@implementation TNLFakeRequestOperation
{
    TNLURLSessionTaskOperation *_ownedURLSessionTaskOperation;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype)initWithURLSessionTaskOperation:(TNLURLSessionTaskOperation *)op
{
    _ownedURLSessionTaskOperation = op;
    return self;
}
#pragma clang pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (instancetype)init
#pragma clang diagnostic pop
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (nullable TNLURLSessionTaskOperation *)URLSessionTaskOperation
{
    return _ownedURLSessionTaskOperation;
}

- (int64_t)operationId
{
    return 0;
}

- (nullable TNLRequestOperationQueue *)requestOperationQueue
{
    return _ownedURLSessionTaskOperation.requestOperationQueue;
}

- (TNLRequestConfiguration *)requestConfiguration
{
    return _ownedURLSessionTaskOperation.requestConfiguration;
}

- (nullable id<TNLRequestDelegate>)requestDelegate
{
    return nil;
}

- (nullable id<TNLRequest>)originalRequest
{
    return _ownedURLSessionTaskOperation.originalRequest;
}

- (nullable id<TNLRequest>)hydratedRequest
{
    return _ownedURLSessionTaskOperation.originalURLRequest;
}

- (nullable TNLResponse *)response
{
    return _ownedURLSessionTaskOperation.finalResponse;
}

- (nullable NSError *)error
{
    return _ownedURLSessionTaskOperation.error;
}

- (TNLRequestOperationState)state
{
    return _ownedURLSessionTaskOperation.state;
}

- (NSUInteger)attemptCount
{
    return 1;
}

- (NSUInteger)retryCount
{
    return 0;
}

- (NSUInteger)redirectCount
{
    return 0;
}

- (float)downloadProgress
{
    return [_ownedURLSessionTaskOperation _network_downloadProgress];
}

- (float)uploadProgress
{
    return [_ownedURLSessionTaskOperation _network_uploadProgress];
}

- (nullable id)context
{
    return nil;
}

- (TNLPriority)priority
{
    return _ownedURLSessionTaskOperation.requestPriority;
}

- (void)cancelWithSource:(id<TNLRequestOperationCancelSource>)source
         underlyingError:(nullable NSError *)optionalUnderlyingError
{
    // no-op
}

- (void)waitUntilFinished
{
    // no-op
}

- (void)waitUntilFinishedWithoutBlockingRunLoop
{
    // no-op
}

@end

static BOOL TNLURLRequestHasBody(NSURLRequest *request, id<TNLRequest> requestPrototype)
{
    if (request.HTTPBody) {
        return YES;
    }

    if ([requestPrototype respondsToSelector:@selector(HTTPBodyFilePath)] && requestPrototype.HTTPBodyFilePath) {
        return YES;
    }

    if ([requestPrototype respondsToSelector:@selector(HTTPBodyStream)] && requestPrototype.HTTPBodyStream) {
        return YES;
    }

    TNLAssertMessage(!request.HTTPBodyStream, @"TNLURLSessionTaskOperation doesn't support HTTPBodyStream!");

    return NO;
}

static NSString *TNLSecCertificateDescription(SecCertificateRef cert)
{
    NSString *serialNumber = nil;
    NSData *serialNumberData = nil;
    if (tnl_available_ios_11) {
        serialNumberData = (NSData *)CFBridgingRelease(SecCertificateCopySerialNumberData(cert, NULL));
    } else {
#if TARGET_OS_OSX
        serialNumberData = (NSData *)CFBridgingRelease(SecCertificateCopySerialNumber(cert, NULL));
#else
#if TARGET_OS_MACCATALYST
        // this is not possible since TARGET_OS_MACCATALYST starts with iOS SDK 13,
        // which will hit the above line
        TNLAssertNever();
#else
        serialNumberData = (NSData *)CFBridgingRelease(SecCertificateCopySerialNumber(cert));
#endif
#endif
    }
    if (serialNumberData) {
        serialNumber = [serialNumberData tnl_hexStringValue];
    }

    NSString *description = (NSString *)CFBridgingRelease(CFCopyDescription(cert)) ?: @"<";
    if ([description hasSuffix:@">"]) {
        description = [description substringToIndex:description.length - 1];
    }

    return [NSString stringWithFormat:@"%@, sn: '%@'>", description, serialNumber];
}

static NSArray<NSString *> *TNLSecTrustGetCertificateChainDescriptions(SecTrustRef trust)
{
    if (!trust) {
        return nil;
    }

    const CFIndex count = SecTrustGetCertificateCount(trust);
    NSMutableArray<NSString *> *certChain = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)count];

    for (CFIndex i = 0; i < count; i++) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, i);
        [certChain addObject:TNLSecCertificateDescription(cert)];
    }

    return [certChain copy];
}

static NSString *TNLWriteDataToTemporaryFile(NSData *data)
{
    static NSString *temporaryFileDir;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        temporaryFileDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
#if !TARGET_OS_IPHONE || TARGET_OS_MACCATALYST
        // platform may be non-sandboxed, or "sandbox" may contain sym-links outside of expected sandbox
        // ensure unique path using bundle-id or a UUID for safety
        NSString *extra = [[NSBundle mainBundle] bundleIdentifier] ?: [kTempFilePrefix stringByAppendingString:[[NSUUID UUID] UUIDString]];
        temporaryFileDir = [temporaryFileDir stringByResolvingSymlinksInPath];
        if (![temporaryFileDir containsString:[NSString stringWithFormat:@"/%@/", extra]]) {
            temporaryFileDir = [temporaryFileDir stringByAppendingPathComponent:extra];
        }
#endif
        [[NSFileManager defaultManager] createDirectoryAtPath:temporaryFileDir withIntermediateDirectories:YES attributes:nil error:NULL];
    });

    NSString *temporaryFilePath = [temporaryFileDir stringByAppendingPathComponent:[kTempFilePrefix stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    [data writeToFile:temporaryFilePath atomically:YES];
    return temporaryFilePath;
}

NS_ASSUME_NONNULL_END

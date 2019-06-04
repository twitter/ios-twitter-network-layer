//
//  TNLRequestEventHandler.h
//  TwitterNetworkLayer
//
//  Created on 8/14/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLAttemptMetrics.h>
#import <TwitterNetworkLayer/TNLRequestConfiguration.h>
#import <TwitterNetworkLayer/TNLRequestOperationState.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLRequestOperation;
@protocol TNLRequestRetryPolicyProvider;

/**
 Block to trigger the enqueuing of a `TNLRequestOperation` instance's
 underlying networking operation
 */
typedef void(^TNLRequestOperationEnqueueNetworkingOperationBlock)(NSArray<NSOperation *> * __nullable dependencies);

/**
 The delegate protocol that is used for event callbacks for a `TNLRequestOperation`

 If the `TNLRequestEventHandler` requires independent threading from the other delegate objects,
 it should dispatch_async to the queue of its choosing since the
 `[TNLRequestDelegate tnl_delegateQueueForRequestOperation:]` is shared between all delegate objects.

 The `[TNLRequestEventHandler tnl_requestOperation:didCompleteWithResponse:]` callback is executed
 from `[TNLRequestDelegate tnl_completionQueueForRequestOperation:]` if defined, or on the main
 queue if not defined.
 All other callbacks are executed from `[TNLRequestDelegate tnl_delegateQueueForRequestOperation:]`
 if defined, or an internal background queue if not defined.
 */
@protocol TNLRequestEventHandler <NSObject>

@optional

/** The operation did transition states */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
      didTransitionFromState:(TNLRequestOperationState)oldState
                     toState:(TNLRequestOperationState)newState;

/** The operation did start a background request.  See `TNLRequestConfiguration`. */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
        didStartRequestWithURLSessionTaskIdentifier:(NSUInteger)taskId
        URLSessionConfigurationIdentifier:(nullable NSString *)configId
        URLSessionSharedContainerIdentifier:(nullable NSString *)sharedContainerIdentifier
        isBackgroundRequest:(BOOL)isBackgroundRequest;

/** The operation did redirect */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
        didRedirectFromURLRequest:(NSURLRequest *)fromRequest
        toURLRequest:(NSURLRequest *)toRequest;

/**
 The operation did have its URL's host sanitized.
 Could be for the initial request, a redirect or a retry.
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
         didSanitizeFromHost:(NSString *)oldHost
                      toHost:(NSString *)host;

/** The operation did update its upload progress */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didUpdateUploadProgress:(float)uploadProgress;

/** The operation did update its download progress */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
   didUpdateDownloadProgress:(float)downloadProgress;

/**
 The operation did received data.
 Requires the _responseDataConsumptionMode_ to be `TNLResponseDataConsumptionModeChunkToDelegateCallback`.
 See `TNLRequestConfiguration`.
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
              didReceiveData:(NSData *)data;

/** The operation did receive an `NSURLResponse` */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
       didReceiveURLResponse:(NSURLResponse *)response;

/** The operation will retry.  See `TNLRequestRetryPolicyProvider`. */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
  willStartRetryFromResponse:(TNLResponse *)responseBeforeRetry
              policyProvider:(id<TNLRequestRetryPolicyProvider>)policyProvider
                  afterDelay:(NSTimeInterval)delay;

/** The operation did retry. See `TNLRequestRetryPolicyProvider`. */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
   didStartRetryFromResponse:(TNLResponse *)responseBeforeRetry
              policyProvider:(id<TNLRequestRetryPolicyProvider>)policyProvider;

/** The operation did complete an attempt.  See `TNLAttemptCompleteDisposition`. */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
        didCompleteAttemptWithResponse:(TNLResponse *)response
        disposition:(TNLAttemptCompleteDisposition)disposition;

/**
 The operation is ready to enqueue the networking work.
 This can be for the initial request or a retry.
 Call the `enqueueBlock` to trigger the enqueue with optionally providing dependencies.
 Default when not implemented is to just enqueue right away.
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
        readyToEnqueueUnderlyingNetworkingOperation:(BOOL)isRetry
        enqueueBlock:(TNLRequestOperationEnqueueNetworkingOperationBlock)enqueueBlock;

/**
 The operation is waiting for connnectivity.
 Only called if `[TNLRequestConfiguration connectivityOptions]` is set to yield waiting for connectivity.
 */
- (void)tnl_requestOperartionIsWaitingForConnectivity:(TNLRequestOperation *)op;

/**
 The operation did complete.
 Arguably the most important delegate callback since it will always be called when an operation ends.
 This is the only `TNLRequestDelegate` callback that executes on
 `[TNLRequestDelegate tnl_completionQueueForRequestOperation:]`.
 If `[TNLRequestDelegate tnl_completionQueueForRequestOperation:]` is not defined, the callback will
 be made from the main queue.

 @param op       the operation that completed
 @param response the response for the operation
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TNLResponse *)response;

@end

NS_ASSUME_NONNULL_END

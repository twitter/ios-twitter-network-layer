//
//  TNLRequestRetryPolicyProvider.h
//  TwitterNetworkLayer
//
//  Created on 5/26/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLRequestRetryPolicyConfiguration;
@class TNLRequestOperation;
@class TNLResponse;

#pragma mark - the Protocol declaration

/**
 The protocol that provides the retry policy for a `TNLRequestOperation`.
 */
@protocol TNLRequestRetryPolicyProvider <NSObject>

@required

/**
 Callback for whether or not to retry a request (required)

 @param op The `TNLRequestOperation` asking to see if it should retry
 @param response the temporary `TNLResponse` composed for this retry query
 @return `YES` to retry, `NO` to not retry
 */
- (BOOL)tnl_shouldRetryRequestOperation:(TNLRequestOperation *)op
                           withResponse:(TNLResponse *)response;

@optional

/**
 Callback for how long to delay before retrying (optional)

 By default, the delay is `0.1` seconds

 @param op The `TNLRequestOperation` that will retry
 @param response the temporary `TNLResponse` composed for this retry query
 @return the interval to delay before retrying.  The minimum value is `0.1` seconds, anything smaller
 will be coersed to be `0.1` seconds.
 */
- (NSTimeInterval)tnl_delayBeforeRetryForRequestOperation:(TNLRequestOperation *)op
                                             withResponse:(TNLResponse *)response;

/**
 Callback for new request configuration of next retry (optional)

 By default, `op.requestConfiguration` will be used (aka _priorConfig_)

 @param op The `TNLRequestOperation` that will retry
 @param response the temporary `TNLResponse` composed for this retry query
 @param priorConfig the `TNLRequestConfiguration` of the prior attempt
 @return the new `TNLRequestConfiguration` of next retry.  `nil` will use _priorConfig_.
 @note Recommend taking the _priorConfig_ and modifying a mutable copy.
 */
- (nullable TNLRequestConfiguration *)tnl_configurationOfRetryForRequestOperation:(TNLRequestOperation *)op
                                                                     withResponse:(TNLResponse *)response
                                                               priorConfiguration:(TNLRequestConfiguration *)priorConfig;

/**
 The operation will retry

 See `[TNLRequestEventHandler tnl_requestOperation:willStartRetryFromResponse:afterDelay:]` and
 `[TNLRequestEventHandler tnl_requestOperation:didStartRetryFromResponse:]`

 @param op                  the `TNLRequestOperation` that will retry
 @param responseBeforeRetry the temporary `TNLResponse` that was composed before querying the retry policy
 @param delay               the delay that will transpire before the retry will begin
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
  willStartRetryFromResponse:(TNLResponse *)responseBeforeRetry
                  afterDelay:(NSTimeInterval)delay;

/**
 The operation did retry

 See `[TNLRequestEventHandler tnl_requestOperation:willStartRetryFromResponse:afterDelay:]` and
 `[TNLRequestEventHandler tnl_requestOperation:didStartRetryFromResponse:]`

 @param op                  the `TNLRequestOperation` that did retry
 @param responseBeforeRetry the temporary `TNLResponse` that the retry is based upon
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
   didStartRetryFromResponse:(TNLResponse *)responseBeforeRetry;

/**
 The `dispatch_queue_t` to execute the `TNLRequestRetryPolicyProvider`'s methods from.
 If `nil` is returned or the method is not implemented, a background queue will be used.
 */
- (nullable dispatch_queue_t)tnl_callbackQueue;

/**
 A unique identifier for this retry policy
 */
- (nullable NSString *)tnl_retryPolicyIdentifier;

@end

#pragma mark - Configurable policy provider protocol

/**
 Protocol for guidance on how to build a concrete retry policy provider using a `TNLRequestRetryPolicyConfiguration`.
 Retry policy providers don't need to adopt this protocol, it's just for convenience.
 */
@protocol TNLConfiguringRetryPolicyProvider <TNLRequestRetryPolicyProvider>

@required
- (instancetype)initWithConfiguration:(nullable TNLRequestRetryPolicyConfiguration *)config;
- (nullable TNLRequestRetryPolicyConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END

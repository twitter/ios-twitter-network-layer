//
//  TNLResponse_Project.h
//  TwitterNetworkLayer
//
//  Created on 9/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLResponse.h"

NS_ASSUME_NONNULL_BEGIN

@class TNLAttemptMetaData;

/*
 * NOTE: this header is private to TNL
 */

@interface TNLResponse ()
- (instancetype)initInternalWithRequest:(nullable id<TNLRequest>)originalRequest
                         operationError:(nullable NSError *)operationError
                                   info:(TNLResponseInfo *)info
                                metrics:(TNLResponseMetrics *)metrics NS_DESIGNATED_INITIALIZER;
@end

@interface TNLResponseMetrics ()

- (void)setEnqueueMachTime:(uint64_t)time;

- (void)addInitialStartWithMachTime:(uint64_t)machTime
                            request:(NSURLRequest *)request;
- (void)addRetryStartWithMachTime:(uint64_t)machTime
                          request:(NSURLRequest *)request;
- (void)addRedirectStartWithMachTime:(uint64_t)machTime
                             request:(NSURLRequest *)request;
- (void)addEnd:(uint64_t)time
      response:(nullable NSHTTPURLResponse *)response
operationError:(nullable NSError *)error;
- (void)addMetaData:(nullable TNLAttemptMetaData *)metaData;
- (void)addTaskMetrics:(nullable NSURLSessionTaskMetrics *)metrics;

- (void)updateCurrentRequest:(NSURLRequest *)request;

- (void)setCompleteMachTime:(uint64_t)time;

- (TNLResponseMetrics *)deepCopyAndTrimIncompleteAttemptMetrics:(BOOL)trimIncompleteAttemptMetrics;

- (void)finalizeMetrics;

@end

NS_ASSUME_NONNULL_END

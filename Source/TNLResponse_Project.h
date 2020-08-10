//
//  TNLResponse_Project.h
//  TwitterNetworkLayer
//
//  Created on 9/17/14.
//  Copyright © 2020 Twitter. All rights reserved.
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

@interface TNLResponseEncodedRequest ()
- (instancetype)initWithSourceRequest:(id<TNLRequest>)request;
@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLResponseMetrics ()

- (void)didEnqueue;

- (void)updateCurrentRequest:(NSURLRequest *)request;

- (void)setCompleteDate:(NSDate *)date machTime:(uint64_t)time;

- (TNLResponseMetrics *)deepCopyAndTrimIncompleteAttemptMetrics:(BOOL)trimIncompleteAttemptMetrics;

- (void)finalizeMetrics;

@end

// TODO: Find way to expose to tests without needing to be Non Direct
@interface TNLResponseMetrics (NonDirect)

- (void)addInitialStartWithDate:(NSDate *)date
                       machTime:(uint64_t)machTime
                        request:(NSURLRequest *)request;
- (void)addRetryStartWithDate:(NSDate *)date
                     machTime:(uint64_t)machTime
                      request:(NSURLRequest *)request;
- (void)addRedirectStartWithDate:(NSDate *)date
                        machTime:(uint64_t)machTime
                         request:(NSURLRequest *)request;
- (void)addEndDate:(NSDate *)date
          machTime:(uint64_t)time
          response:(nullable NSHTTPURLResponse *)response
    operationError:(nullable NSError *)error;
- (void)addMetaData:(nullable TNLAttemptMetaData *)metaData
        taskMetrics:(nullable NSURLSessionTaskMetrics *)metrics;

@end

NS_ASSUME_NONNULL_END

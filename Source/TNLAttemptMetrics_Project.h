//
//  TNLAttemptMetrics_Project.h
//  TwitterNetworkLayer
//
//  Created on 1/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TNLAttemptMetrics.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

#if !TARGET_OS_WATCH
@class TNLCommunicationAgent;
#endif

@interface TNLAttemptMetrics (Project)

- (void)setMetaData:(nullable TNLAttemptMetaData *)metaData;
- (void)setEndDate:(nonnull NSDate *)endDate machTime:(uint64_t)time;
- (void)setURLResponse:(nullable NSHTTPURLResponse *)response;
- (void)setOperationError:(nullable NSError *)error;
- (void)setTaskTransactionMetrics:(nullable NSURLSessionTaskTransactionMetrics *)taskMetrics NS_AVAILABLE(10_12, 10_0);
#if !TARGET_OS_WATCH
- (void)setCommunicationMetricsWithAgent:(nullable TNLCommunicationAgent *)agent;
#endif
- (void)updateRequest:(NSURLRequest *)request;
- (void)finalizeMetrics;

@end

NS_ASSUME_NONNULL_END

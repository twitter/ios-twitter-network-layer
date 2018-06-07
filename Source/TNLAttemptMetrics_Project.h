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

@class TNLCommunicationAgent;

@interface TNLAttemptMetrics (Project)

- (void)setMetaData:(nullable TNLAttemptMetaData *)metaData;
- (void)setEndMachTime:(uint64_t)time;
- (void)setURLResponse:(nullable NSHTTPURLResponse *)response;
- (void)setOperationError:(nullable NSError *)error;
- (void)setTaskTransactionMetrics:(nullable NSURLSessionTaskTransactionMetrics *)taskMetrics NS_AVAILABLE(10_12, 10_0);
- (void)setCommunicationMetricsWithAgent:(nullable TNLCommunicationAgent *)agent;
- (void)updateRequest:(NSURLRequest *)request;
- (void)finalizeMetrics;

@end

NS_ASSUME_NONNULL_END

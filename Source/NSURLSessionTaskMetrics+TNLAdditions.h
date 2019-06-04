//
//  NSURLSessionTaskMetrics+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 7/25/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURLSessionTaskMetrics`
 */
@interface NSURLSessionTaskMetrics (TNLAdditions)

/**
 A detailed description of the metrics instance and its transaction metrics
 */
- (NSString *)tnl_detailedDescription;

/**
 A dictionary representation of the task metrics
 */
- (NSDictionary<NSString *, id> *)tnl_dictionaryValue;

@end

/**
 __TNL__ additions for `NSURLSessionTaskTransactionMetrics`
 */
@interface NSURLSessionTaskTransactionMetrics (TNLAdditions)

/**
 A dictionary representation of the transaction metrics
 */
- (NSDictionary<NSString *, id> *)tnl_dictionaryValue;

/**
 returns the earliest date of all the timing dates
 */
- (nullable NSDate *)tnl_earliestDate;

/**
 return the latest date of all the timing dates
 */
- (nullable NSDate *)tnl_latestDate;

/**
 The known duration of the task.
 If a task is cancelled/fails midway through a phase, the timing metrics can be cut off.
 If a task completes, the duration will be accurate.
 */
- (NSTimeInterval)tnl_knownDuration;

/**
 returns a string describing the timings
 */
- (NSString *)tnl_timingDescription;

/** convenience method for TCP start if connect includes TCP connect */
@property (nonatomic, readonly, nullable) NSDate *tnl_transportConnectionStartDate;
/** convenience method for TCP end if connect includes TCP connect */
@property (nonatomic, readonly, nullable) NSDate *tnl_transportConnectionEndDate;

/** duration of domain lookup (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_domainLookupDuration;
/** duration of entire connect (inclusive of TCP connect and secure connect) (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_connectDuration;
/** duration of TCP connect (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_transportConnectionDuration;
/** duration of secure connection (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_secureConnectionDuration;
/** duration of request (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_requestSendDuration;
/** duration of server time (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_serverTimeDuration;
/** duration of response (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_responseReceiveDuration;
/** total duration (`NSTimeInterval`) */
- (nullable NSNumber *)tnl_totalDuration;

/**
 duration of secure connection, extended (will consider from secure start to max of connect end and
 secure end) (`NSTimeInterval`)
 */
- (nullable NSNumber *)tnl_secureConnectionDurationExt;

@end

NS_ASSUME_NONNULL_END

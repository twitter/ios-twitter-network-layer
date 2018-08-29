//
//  NSURLSessionTaskMetrics+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 7/25/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "NSURLSessionTaskMetrics+TNLAdditions.h"
#import "TNL_Project.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSURLSessionTaskMetrics (TNLAdditions)

- (NSString *)tnl_detailedDescription
{
    NSMutableString *string = [[NSMutableString alloc] init];

    [string appendFormat:@"<%@ %p: redirectCount=%tu, taskInterval=%.3fs, transactionMetrics=[", NSStringFromClass([self class]), self, self.redirectCount, self.taskInterval.duration];

    for (NSURLSessionTaskTransactionMetrics *transactionMetrics in self.transactionMetrics) {
        NSDictionary *d = [transactionMetrics tnl_dictionaryValue];
        [string appendFormat:@"\n%@,", d];
    }

    [string appendString:@"\n]>"];

    return string;
}

- (NSDictionary<NSString *, id> *)tnl_dictionaryValue
{
    NSMutableDictionary<NSString *, id> *taskMetrics = [[NSMutableDictionary alloc] init];

    taskMetrics[@"redirectCount"] = @(self.redirectCount);
    taskMetrics[@"taskInterval"] = self.taskInterval;
    taskMetrics[@"taskDuration"] = @(self.taskInterval.duration);

    NSMutableArray<NSDictionary *> *transactionMetricsArray = [[NSMutableArray alloc] initWithCapacity:self.transactionMetrics.count];
    for (NSURLSessionTaskTransactionMetrics *transactionMetrics in self.transactionMetrics) {
        [transactionMetricsArray addObject:[transactionMetrics tnl_dictionaryValue]];
    }
    taskMetrics[@"transactionMetrics"] = transactionMetricsArray;

    return taskMetrics;
}

@end

@implementation NSURLSessionTaskTransactionMetrics (TNLAdditions)

- (NSDictionary<NSString *, id> *)tnl_dictionaryValue
{
    NSMutableDictionary<NSString *, id> *d = [[NSMutableDictionary alloc] init];

    d[@"statusCode"] = @([(NSHTTPURLResponse *)self.response statusCode]);

#define APPLY_VALUE(key, value) \
    do { \
        id valueObj = (value); \
        if (valueObj) { \
            d[(key)] = valueObj; \
        } \
    } while (NO)

    APPLY_VALUE(@"URL", self.request.URL);
    APPLY_VALUE(@"protocol", self.networkProtocolName);

    APPLY_VALUE(@"dns", [self tnl_domainLookupDuration]);
    APPLY_VALUE(@"connect", [self tnl_connectDuration]);
    APPLY_VALUE(@"tcp", [self tnl_transportConnectionDuration]);
    APPLY_VALUE(@"secure", [self tnl_secureConnectionDuration]);
    APPLY_VALUE(@"request", [self tnl_requestSendDuration]);
    APPLY_VALUE(@"server", [self tnl_serverTimeDuration]);
    APPLY_VALUE(@"response", [self tnl_responseReceiveDuration]);
    APPLY_VALUE(@"total", [self tnl_totalDuration]);

#undef APPLY_VALUE

    switch (self.resourceFetchType) {
        case NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad:
            d[@"load"] = @"network";
            break;
        case NSURLSessionTaskMetricsResourceFetchTypeServerPush:
            d[@"load"] = @"push";
            break;
        case NSURLSessionTaskMetricsResourceFetchTypeLocalCache:
            d[@"load"] = @"cache";
            break;
        default:
            d[@"load"] = @"unknown";
            break;
    }

    if (!self.reusedConnection) {
        d[@"newConnection"] = @"true";
    }

    if (self.proxyConnection) {
        d[@"proxy"] = @"true";
    }

    return d;
}

- (nullable NSDate *)tnl_transportConnectionStartDate
{
    return self.connectStartDate;
}

- (nullable NSDate *)tnl_transportConnectionEndDate
{
    return self.secureConnectionStartDate ?: self.connectEndDate;
}

- (nullable NSNumber *)tnl_domainLookupDuration
{
    NSDate *endDate = self.domainLookupEndDate;
    if (!endDate) {
        return nil;
    }

    NSDate *startDate = self.domainLookupStartDate;
    TNLAssert(startDate != nil);
    return @([endDate timeIntervalSinceDate:startDate]);
}

- (nullable NSNumber *)tnl_connectDuration
{
    NSDate *endDate = self.connectEndDate;
    if (!endDate) {
        return nil;
    }

    NSDate *startDate = self.connectStartDate;
    TNLAssert(startDate != nil);
    return @([endDate timeIntervalSinceDate:startDate]);
}

- (nullable NSNumber *)tnl_transportConnectionDuration
{
    NSDate *startDate = self.tnl_transportConnectionStartDate;
    if (!startDate) {
        return nil;
    }
    NSDate *endDate = self.tnl_transportConnectionEndDate;
    if (!endDate) {
        return nil;
    }

    return @([endDate timeIntervalSinceDate:startDate]);
}

- (nullable NSNumber *)tnl_secureConnectionDuration
{
    NSDate *endDate = self.secureConnectionEndDate;
    if (!endDate) {
        return nil;
    }

    NSDate *startDate = self.secureConnectionStartDate;
    TNLAssert(startDate != nil);
    return @([endDate timeIntervalSinceDate:startDate]);
}

- (nullable NSNumber *)tnl_requestSendDuration
{
    NSDate *endDate = self.requestEndDate;
    if (!endDate) {
        return nil;
    }

    NSDate *startDate = self.requestStartDate;
    TNLAssert(startDate != nil);
    return @([endDate timeIntervalSinceDate:startDate]);
}

- (nullable NSNumber *)tnl_serverTimeDuration
{
    NSDate *requestEndDate = self.requestEndDate;
    if (!requestEndDate) {
        return nil;
    }
    NSDate *responseStartDate = self.responseStartDate;
    if (!responseStartDate) {
        return nil;
    }

    return @([responseStartDate timeIntervalSinceDate:requestEndDate]);
}

- (nullable NSNumber *)tnl_responseReceiveDuration
{
    NSDate *endDate = self.responseEndDate;
    if (!endDate) {
        return nil;
    }

    NSDate *startDate = self.responseStartDate;
    TNLAssert(startDate != nil);
    return @([endDate timeIntervalSinceDate:startDate]);
}

- (nullable NSNumber *)tnl_totalDuration
{
    NSDate *fetchStartDate = self.fetchStartDate;
    if (!fetchStartDate) {
        return nil;
    }
    NSDate *responseEndDate = self.responseEndDate;
    if (!responseEndDate) {
        return nil;
    }

    return @([responseEndDate timeIntervalSinceDate:fetchStartDate]);
}

- (nullable NSNumber *)tnl_secureConnectionDurationExt
{
    NSDate *connectEndDate = self.connectEndDate;
    if (!connectEndDate) {
        return self.tnl_secureConnectionDuration;
    }
    NSDate *startDate = self.secureConnectionStartDate;
    if (!startDate) {
        return nil;
    }
    NSDate *endDate = [self.secureConnectionEndDate laterDate:connectEndDate];
    if (!endDate) {
        return nil;
    }

    return @([endDate timeIntervalSinceDate:startDate]);
}

@end

NS_ASSUME_NONNULL_END

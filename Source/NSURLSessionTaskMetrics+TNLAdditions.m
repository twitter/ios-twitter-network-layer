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

    if (self.request.URL) {
        d[@"URL"] = self.request.URL;
    }

    if (self.networkProtocolName) {
        d[@"protocol"] = self.networkProtocolName;
    }

#define APPLY_VALUE(key, value) \
    do { \
        id valueObj = (value); \
        if (valueObj) { \
            d[(key)] = valueObj; \
        } \
    } while (NO)


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
    if (self.domainLookupEndDate) {
        TNLAssert(self.domainLookupStartDate != nil);
        return @([self.domainLookupEndDate timeIntervalSinceDate:self.domainLookupStartDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_connectDuration
{
    if (self.connectEndDate) {
        TNLAssert(self.connectStartDate != nil);
        return @([self.connectEndDate timeIntervalSinceDate:self.connectStartDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_transportConnectionDuration
{
    NSDate *startDate = self.tnl_transportConnectionStartDate;
    NSDate *endDate = self.tnl_transportConnectionEndDate;
    if (startDate && endDate) {
        return @([endDate timeIntervalSinceDate:startDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_secureConnectionDuration
{
    if (self.secureConnectionEndDate) {
        TNLAssert(self.secureConnectionStartDate != nil);
        return @([self.secureConnectionEndDate timeIntervalSinceDate:self.secureConnectionStartDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_requestSendDuration
{
    if (self.requestEndDate) {
        TNLAssert(self.requestStartDate != nil);
        return @([self.requestEndDate timeIntervalSinceDate:self.requestStartDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_serverTimeDuration
{
    if (self.requestEndDate && self.responseStartDate) {
        return @([self.responseStartDate timeIntervalSinceDate:self.requestEndDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_responseReceiveDuration
{
    if (self.responseEndDate) {
        TNLAssert(self.responseStartDate != nil);
        return @([self.responseEndDate timeIntervalSinceDate:self.responseStartDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_totalDuration
{
    if (self.fetchStartDate && self.responseEndDate) {
        return @([self.responseEndDate timeIntervalSinceDate:self.fetchStartDate]);
    }
    return nil;
}

- (nullable NSNumber *)tnl_secureConnectionDurationExt
{
    if (!self.connectEndDate) {
        return self.tnl_secureConnectionDuration;
    }

    NSDate *startDate = self.secureConnectionStartDate;
    NSDate *endDate = [self.secureConnectionEndDate laterDate:self.connectEndDate];
    if (startDate && endDate) {
        return @([endDate timeIntervalSinceDate:startDate]);
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END

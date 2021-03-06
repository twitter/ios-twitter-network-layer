//
//  NSURLSessionTaskMetrics+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 7/25/16.
//  Copyright © 2020 Twitter. All rights reserved.
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
    return [self _tnl_dictionaryValue:NO];
}

- (NSDictionary<NSString *, id> *)tnl_dictionaryDescription
{
    return [self _tnl_dictionaryValue:YES];
}

- (NSMutableDictionary<NSString *, id> *)_tnl_dictionaryValue:(BOOL)sanitizeForSerialization TNL_OBJC_DIRECT
{
    NSMutableDictionary<NSString *, id> *d = [self _tnl_metadata:sanitizeForSerialization];

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

    d[@"statusCode"] = @([(NSHTTPURLResponse *)self.response statusCode]);
    if (sanitizeForSerialization) {
        APPLY_VALUE(@"URL", self.request.URL.absoluteString);
    } else {
        APPLY_VALUE(@"URL", self.request.URL);
    }

#undef APPLY_VALUE

    return d;
}

- (NSDictionary<NSString *, id> *)tnl_medadata
{
    return [self _tnl_metadata:NO];
}

- (NSMutableDictionary<NSString *, id> *)_tnl_metadata:(BOOL)sanitizeForSerialization TNL_OBJC_DIRECT
{
    NSMutableDictionary<NSString *, id> *d = [[NSMutableDictionary alloc] init];

#define APPLY_VALUE(key, value) \
    do { \
        id valueObj = (value); \
        if (valueObj) { \
            d[(key)] = valueObj; \
        } \
    } while (NO)

    APPLY_VALUE(@"protocol", self.networkProtocolName);

    d[@"load"] = self.tnl_resourceFetchTypeDebugString;
    d[@"newConnection"] = @(!self.reusedConnection);
    d[@"proxy"] = @(self.proxyConnection);

#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
#define TNL_CAN_LOG_NEW_METRICS 1
#elif TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
#define TNL_CAN_LOG_NEW_METRICS 1
#endif

#if TNL_CAN_LOG_NEW_METRICS
    if (tnl_available_ios_13) {
        d[@"header_tx"] = @(self.countOfRequestHeaderBytesSent);
        d[@"body_tx"] = @(self.countOfRequestBodyBytesSent);
        d[@"body_bytes"] = @(self.countOfRequestBodyBytesBeforeEncoding);

        d[@"header_rx"] = @(self.countOfResponseHeaderBytesReceived);
        d[@"body_rx"] = @(self.countOfResponseBodyBytesReceived);
        d[@"body_bytes"] = @(self.countOfResponseBodyBytesAfterDecoding);

        APPLY_VALUE(@"localAddress", self.localAddress);
        APPLY_VALUE(@"localPort", self.localPort);
        APPLY_VALUE(@"remoteAddress", self.remoteAddress);
        APPLY_VALUE(@"remotePort", self.remotePort);
        APPLY_VALUE(@"tlsVersion", self.negotiatedTLSProtocolVersion);
        APPLY_VALUE(@"tlsCSuite", self.negotiatedTLSCipherSuite);

        d[@"cellular"] = @(self.isCellular);
        d[@"expensive"] = @(self.isExpensive);
        d[@"constrained"] = @(self.isConstrained);
        d[@"multipath"] = @(self.isMultipath);
    }
#endif

#undef APPLY_VALUE

    return d;
}

- (NSString *)tnl_resourceFetchTypeDebugString
{
    switch (self.resourceFetchType) {
        case NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad:
            return @"network";
        case NSURLSessionTaskMetricsResourceFetchTypeServerPush:
            return @"push";
        case NSURLSessionTaskMetricsResourceFetchTypeLocalCache:
            return @"cache";
        default:
            return @"unknown";
    }
}

- (NSString *)tnl_timingDescription
{
    NSDate *earliestDate = self.tnl_earliestDate;
    if (!earliestDate) {
        return @"<>";
    }

    NSDate *previousDate = earliestDate;
    NSDate *currentDate = nil;
    NSTimeInterval delta = 0;
    NSMutableString *timing = [[NSMutableString alloc] init];
    [timing appendString:@"<"];

#define APPEND_DATE(dateName) \
    do { \
        currentDate = [self dateName##Date ]; \
        if (currentDate) { \
            if (timing.length > 1) { \
                [timing appendString:@"|"]; \
            } \
            delta = [currentDate timeIntervalSinceDate:previousDate]; \
            [timing appendFormat:@" (%c%li) %@ ", (delta < 0) ? '-' : '+', labs((long)(delta * 1000.0)), @"" #dateName ]; \
            previousDate = currentDate; \
        } \
    } while (0)

    APPEND_DATE(fetchStart);
    APPEND_DATE(domainLookupStart);
    APPEND_DATE(domainLookupEnd);
    APPEND_DATE(connectStart);
    APPEND_DATE(secureConnectionStart);
    APPEND_DATE(secureConnectionEnd);
    APPEND_DATE(connectEnd);
    APPEND_DATE(requestStart);
    APPEND_DATE(requestEnd);
    APPEND_DATE(responseStart);
    APPEND_DATE(responseEnd);

#undef APPEND_DATE

    [timing appendString:@">"];
    return [timing copy];
}

- (nullable NSDate *)tnl_earliestDate
{
    NSDate *earliest = self.fetchStartDate;

#define EARLIER(date) \
    do { \
        NSDate *__d = [self date ]; \
        if (__d) { \
            earliest = (earliest) ? [earliest earlierDate:__d] : __d; \
        } \
    } while (0)

    EARLIER(domainLookupStartDate);
    EARLIER(connectStartDate);
    EARLIER(secureConnectionStartDate);
    EARLIER(requestStartDate);
    EARLIER(responseStartDate);

#undef EARLIER

    return earliest;
}

- (nullable NSDate *)tnl_latestDate
{
    NSDate *latest = self.responseEndDate;

#define LATER(date) \
    do { \
        NSDate *__d = [self date ]; \
        if (__d) { \
            latest = (latest) ? [latest laterDate:__d] : __d; \
        } \
    } while (0)

    LATER(responseStartDate);
    LATER(requestEndDate);
    LATER(requestStartDate);
    LATER(connectEndDate);
    LATER(secureConnectionEndDate);
    LATER(secureConnectionStartDate);
    LATER(connectStartDate);
    LATER(domainLookupEndDate);
    LATER(domainLookupStartDate);
    LATER(fetchStartDate);

#undef LATER

    return latest;
}

- (NSTimeInterval)tnl_knownDuration
{
    NSDate *earliestDate = self.tnl_earliestDate;
    NSDate *latestDate = self.tnl_latestDate;

    if (!earliestDate || !latestDate) {
        return 0;
    }

    return [latestDate timeIntervalSinceDate:earliestDate];
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

    const NSTimeInterval duration = [responseStartDate timeIntervalSinceDate:requestEndDate];
    if (duration < 0.0) {
        // response started BEFORE the request ended...strange...
        return nil;
    }
    return @(duration);
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

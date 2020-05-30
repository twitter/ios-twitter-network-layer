//
//  TNLXNetworkHeuristicObserver.m
//  TwitterNetworkLayer
//
//  Created on 1/26/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLXNetworkHeuristicObserver.h"

#define LOG_STATS_HEARTBEAT 0

@implementation TNLXNetworkHeuristicObserver
{
    dispatch_queue_t _queue;
    dispatch_source_t _timer;

    NSTimeInterval _totalAttemptTime;
    NSTimeInterval _totalOperationTime;
    UInt64 _totalLayer8BytesUp;
    UInt64 _totalLayer8BytesDown;
    UInt64 _retryCount;
    UInt64 _redirectCount;
    UInt64 _attemptCount;
    UInt64 _cancelCount;
}

+ (instancetype)sharedInstance
{
    static TNLXNetworkHeuristicObserver *sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[TNLXNetworkHeuristicObserver alloc] init];
        [[TNLGlobalConfiguration sharedInstance] addNetworkObserver:sInstance];
    });
    return sInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _queue = dispatch_queue_create("TNLXNetworkHeuristicObserver.queue", DISPATCH_QUEUE_SERIAL);
#if LOG_STATS_HEARTBEAT
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        int64_t repeatInterval = (int64_t)(4.0 * (double)NSEC_PER_SEC);
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, repeatInterval), (uint64_t)repeatInterval, (uint64_t)(1.0 * (double)NSEC_PER_SEC));
        dispatch_source_set_event_handler(_timer, ^{
            NSLog(@"%@", [self dictionaryValue]);
        });
        dispatch_resume(_timer);
#endif
    }
    return self;
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteAttemptWithIntermediateResponse:(TNLResponse *)response disposition:(TNLAttemptCompleteDisposition)disposition
{
    TNLAttemptMetrics *metrics = response.metrics.attemptMetrics.lastObject;
    dispatch_async(_queue, ^{
        NSTimeInterval duration = metrics.duration;
        TNLAttemptMetaData *metaData = metrics.metaData;
        if (duration >= 0.0) {
            self->_totalAttemptTime += duration;
        }
        if (metaData.layer8BodyBytesReceived > 0) {
            self->_totalLayer8BytesDown += (UInt64)metaData.layer8BodyBytesReceived;
        }
        if (metaData.layer8BodyBytesTransmitted > 0) {
            self->_totalLayer8BytesUp += (UInt64)metaData.layer8BodyBytesTransmitted;
        }
        switch (metrics.attemptType) {
            case TNLAttemptTypeInitial:
                break;
            case TNLAttemptTypeRedirect:
                self->_redirectCount++;
                break;
            case TNLAttemptTypeRetry:
                self->_retryCount++;
                break;
        }
        self->_attemptCount++;
    });
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteWithResponse:(TNLResponse *)response
{
    dispatch_async(_queue, ^{
        NSTimeInterval duration = response.metrics.totalDuration;
        if (duration >= 0.0) {
            self->_totalOperationTime += duration;
        }
        if ([response.operationError.domain isEqualToString:TNLErrorDomain] && response.operationError.code == TNLErrorCodeRequestOperationCancelled) {
            self->_cancelCount++;
        }
    });
}

- (NSDictionary *)dictionaryValue
{
    return @{
             @"attemptTime" : @(_totalAttemptTime),
             @"operationTime" : @(_totalOperationTime),
             @"l8_rx" : @(_totalLayer8BytesDown),
             @"l8_tx" : @(_totalLayer8BytesUp),
             @"attemptCount" : @(_attemptCount),
             @"redirectCount" : @(_redirectCount),
             @"retryCount" : @(_retryCount),
             @"cancelCount" : @(_cancelCount),
             };
}

@end

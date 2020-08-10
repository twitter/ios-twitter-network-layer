//
//  TNLBackoff.m
//  TwitterNetworkLayer
//
//  Created on 3/31/20.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSDictionary+TNLAdditions.h"
#import "NSURLResponse+TNLAdditions.h"
#import "TNLBackoff.h"

NS_ASSUME_NONNULL_BEGIN

const NSTimeInterval TNLSimpleRetryAfterBackoffValueDefault = 1.0;
const NSTimeInterval TNLSimpleRetryAfterBackoffValueMinimum = 0.1;
const NSTimeInterval TNLSimpleRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway = 10.0;

@implementation TNLSimpleBackoffBehaviorProvider

- (TNLBackoffBehavior)tnl_backoffBehaviorForURL:(NSURL *)URL
                                responseHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers
{
    NSTimeInterval backoff = TNLSimpleRetryAfterBackoffValueDefault;

    NSString *retryAfterString = [headers tnl_objectForCaseInsensitiveKey:@"retry-after"];
    id retryAfterValue = [NSHTTPURLResponse tnl_parseRetryAfterValueFromString:retryAfterString];
    if (retryAfterValue) {
        backoff = [NSHTTPURLResponse tnl_delayFromRetryAfterValue:retryAfterValue];
    }

    if (backoff < TNLSimpleRetryAfterBackoffValueMinimum) {
        backoff = TNLSimpleRetryAfterBackoffValueMinimum;
    } else if (backoff > TNLSimpleRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway) {
        backoff = TNLSimpleRetryAfterBackoffValueDefault;
    }

    return TNLBackoffBehaviorMake(backoff, self.serializeDuration, self.serialDelayDuration);
}

@end

@implementation TNLSimpleBackoffSignaler

- (BOOL)tnl_shouldSignalBackoffForURL:(NSURL *)URL
                                 host:(nullable NSString *)host
                           statusCode:(TNLHTTPStatusCode)statusCode
                      responseHeaders:(nullable NSDictionary<NSString *,NSString *> *)responseHeaders
{
    return TNLHTTPStatusCodeServiceUnavailable == statusCode;
}

@end

NS_ASSUME_NONNULL_END

//
//  NSCachedURLResponse+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 11/22/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import "NSCachedURLResponse+TNLAdditions.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * const kTNLLocalCacheHeaderFieldName = @"x-tnl-local-cache";
static NSString * const kTNLLocalCacheHeaderFieldHitValue = @"hit";

@implementation NSCachedURLResponse (TNLCacheAdditions)

- (NSCachedURLResponse *)tnl_flaggedCachedResponse
{
    NSCachedURLResponse *response = self;
    NSURLResponse *URLResponse = response.response;
    if ([URLResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *HTTPResponse = (id)URLResponse;
        if (![HTTPResponse.allHeaderFields[kTNLLocalCacheHeaderFieldName] isEqualToString:kTNLLocalCacheHeaderFieldHitValue]) {
            NSMutableDictionary *allHeaderFields = [HTTPResponse.allHeaderFields mutableCopy];
            allHeaderFields[kTNLLocalCacheHeaderFieldName] = kTNLLocalCacheHeaderFieldHitValue;
            HTTPResponse = [[NSHTTPURLResponse alloc] initWithURL:HTTPResponse.URL
                                                       statusCode:HTTPResponse.statusCode
                                                      HTTPVersion:@"1.1"
                                                     headerFields:allHeaderFields];
            response = [[NSCachedURLResponse alloc] initWithResponse:HTTPResponse
                                                                data:response.data
                                                            userInfo:response.userInfo
                                                       storagePolicy:response.storagePolicy];
        }
    }
    return response;
}

@end

@implementation NSURLResponse (TNLCacheAdditions)

- (BOOL)tnl_wasCachedResponse
{
    if ([self isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *HTTPResponse = (id)self;
        NSString *localCacheValue = HTTPResponse.allHeaderFields[kTNLLocalCacheHeaderFieldName];
        return [localCacheValue isEqualToString:kTNLLocalCacheHeaderFieldHitValue];
    }

    return NO;
}

@end

NS_ASSUME_NONNULL_END

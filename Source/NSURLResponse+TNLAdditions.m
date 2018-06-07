//
//  NSURLResponse+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 11/13/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#include <objc/runtime.h>

#import "NSDictionary+TNLAdditions.h"
#import "NSURLResponse+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLHTTP.h"

NS_ASSUME_NONNULL_BEGIN

static const char TNLContentEncodingAssociatedObjectKey[] = "tnl.content.encoding";

@implementation NSURLResponse (TNLAdditions)

- (BOOL)tnl_isEqualToResponse:(nullable NSURLResponse *)response
{
    if ([self isEqual:response]) {
        return YES;
    }

    IS_EQUAL_OBJ_PROP_CHECK(self, response, URL);
    IS_EQUAL_OBJ_PROP_CHECK(self, response, MIMEType);

    if (self.expectedContentLength != response.expectedContentLength) {
        return NO;
    }

    IS_EQUAL_OBJ_PROP_CHECK(self, response, textEncodingName);
    IS_EQUAL_OBJ_PROP_CHECK(self, response, suggestedFilename);

    return YES;
}

@end

@implementation NSHTTPURLResponse (TNLAdditions)

+ (nullable id)tnl_parseRetryAfterValueFromString:(nullable NSString *)retryAfterStringValue
{
    // Parsing of value is based on the definition in the HTTP/1.1 spec
    // http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html Section 14.37

    retryAfterStringValue = [retryAfterStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (retryAfterStringValue.length == 0) {
        return nil;
    }

    // Manually parse integer
    uint64_t invalidBitsMask = 0xFFFFFFFF80000000;
    uint64_t retryAfterDuration = 0;
    for (NSUInteger i = 0; i < retryAfterStringValue.length; i++) {
        unichar c = [retryAfterStringValue characterAtIndex:i];
        if (c < '0' || c > '9') {
            // Value is not a positive integer
            retryAfterDuration = invalidBitsMask;
            break;
        }
        retryAfterDuration *= 10;
        retryAfterDuration += (c - '0');
        if (TNL_BITMASK_INTERSECTS_FLAGS(retryAfterDuration, invalidBitsMask)) {
            // Overflow, invalid 32 bit integer
            break;
        }
    }

    if (TNL_BITMASK_EXCLUDES_FLAGS(retryAfterDuration, invalidBitsMask)) {
        // value is an integer (and therefore a delay)
        TNLAssert(retryAfterDuration <= INT32_MAX);
        return @((NSTimeInterval)retryAfterDuration);
    } else {
        // value is a string that MUST be an HTTP date (otherwise, the value is invalid)
        return TNLHTTPDateFromString(retryAfterStringValue, NULL);
    }
}

- (nullable id)tnl_parsedRetryAfterValue
{
    NSString *retryAfter = self.allHeaderFields[@"Retry-After"];
    return [[self class] tnl_parseRetryAfterValueFromString:retryAfter];
}

- (BOOL)tnl_isEqualToResponse:(nullable NSURLResponse *)response
{
    if ([self isEqual:response]) {
        return YES;
    }

    if (![super tnl_isEqualToResponse:response]) {
        return NO;
    }

    NSHTTPURLResponse *httpResponse = (id)response;
    if (![httpResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }

    if (self.statusCode != httpResponse.statusCode) {
        return NO;
    }

    NSDictionary *selfLowercaseHeaders = [self.allHeaderFields tnl_mutableCopyWithLowercaseKeys];
    NSDictionary *otherLowercaseHeaders = [httpResponse.allHeaderFields tnl_mutableCopyWithLowercaseKeys];
    if (![selfLowercaseHeaders isEqualToDictionary:otherLowercaseHeaders]) {
        return NO;
    }

    return YES;
}

- (nullable NSString *)tnl_contentEncoding
{
    NSString *contentEncoding = objc_getAssociatedObject(self, TNLContentEncodingAssociatedObjectKey);
    if (!contentEncoding) {
        contentEncoding = [self.allHeaderFields tnl_objectsForCaseInsensitiveKey:@"Content-Encoding"].firstObject;
        objc_setAssociatedObject(self, TNLContentEncodingAssociatedObjectKey, contentEncoding ?: [NSNull null], OBJC_ASSOCIATION_RETAIN /*atomic*/);
    }
    if (contentEncoding == (id)[NSNull null]) {
        contentEncoding = nil;
    }
    return contentEncoding;
}

- (long long)tnl_expectedResponseBodySize
{
    NSString *contentLengthString = [self.allHeaderFields tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject;
    const long long headerContentLength = (contentLengthString) ? [contentLengthString longLongValue] : -1;
    if (headerContentLength >= 0) {
        return headerContentLength;
    }
    return self.expectedContentLength;
}

- (long long)tnl_expectedResponseBodyExpandedDataSize
{
    long long contentLength = self.expectedContentLength;
    if (contentLength <= 0) {
        NSString *contentLengthString = [self.allHeaderFields tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject;
        if (contentLengthString) {
            contentLength = [contentLengthString longLongValue];
        } else {
            contentLength = -1;
        }
    }
    return contentLength;
}

@end

NS_ASSUME_NONNULL_END

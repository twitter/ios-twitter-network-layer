//
//  NSURLResponse+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 11/13/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURLResponse`
 */
@interface NSURLResponse (TNLAdditions)

/**
 Determine if the receiver is equal to the provided _response_.   `[NSURLResponse isEqual:]` is only
 a pointer test.
 */
- (BOOL)tnl_isEqualToResponse:(nullable NSURLResponse *)response;

@end

/**
 __TNL__ additions for `NSHTTPURLResponse`
 */
@interface NSHTTPURLResponse (TNLAdditions)

/**
 Convenience method for converting the `"Retry-After"` value into a delay.
 Returns `NSDate` if the string was for a date.
 Returns `NSNumber` wrapped `NSTimeInterval` (aka `double`) if the string was for a delay.
 Returns `nil` if the string could not be parsed.
 */
+ (nullable id)tnl_parseRetryAfterValueFromString:(nullable NSString *)retryAfterValueString;

/**
 Calls `tnl_parseRetryAfterValueFromString:` with the `"Retry-After"` response header's value as the
 provided string.
 */
- (nullable id)tnl_parsedRetryAfterValue;

/**
 Determine if the receiver is equal to the provided _response_.
 __See Also:__ `[NSURLResponse(TNLAdditions) tnl_isEqualToResponse:]`.
 */
- (BOOL)tnl_isEqualToResponse:(nullable NSHTTPURLResponse *)response;

/**
 Returns the response's `Content-Encoding`, or `nil` if none provided
 */
- (nullable NSString *)tnl_contentEncoding;

/**
 Returns the response's expected body size (_Content-Length_), or `-1` if unknown
 */
- (long long)tnl_expectedResponseBodySize;

/**
 Returns the response's expected body expanded size (body after decoding), or `-1` if unknown
 */
- (long long)tnl_expectedResponseBodyExpandedDataSize;

@end

NS_ASSUME_NONNULL_END

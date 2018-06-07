//
//  TNLHTTPHeaderProvider.h
//  TwitterNetworkLayer
//
//  Created on 4/13/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TNLRequest;

/**
 Use this protocol to provide accessors to default and/or override HTTP header fields applied to
 requests of a `TNLRequestOperation`.
 */
@protocol TNLHTTPHeaderProvider <NSObject>

@optional

/**
 A dictionary of all _HTTP_ header fields to use on a `TNLRequest` by default.
 These values will be overridden by any fields with the same name provided by
 `[TNLRequest allHTTPHeaderFields]`.

 @param request         the `TNLRequest` that default HTTP headers will be applied to
 @param URLRequest      the `NSURLRequest` that _request_ has yielded that the HTTP headers will be applied to
 */
- (nullable NSDictionary<NSString *, NSString *> *)tnl_allDefaultHTTPHeaderFieldsForRequest:(id<TNLRequest>)request
                                                                                 URLRequest:(NSURLRequest *)URLRequest;

/**
 A dictionary of all _HTTP_ header fields to override on a `TNLRequest`.
 These values will override whatever was provided by `[TNLRequest allHTTPHeaderFields]`.

 @param request         the `TNLRequest` that override HTTP headers will be applied to
 @param URLRequest      the `NSURLRequest` that _request_ has yielded that the HTTP headers will be applied to
 */
- (nullable NSDictionary<NSString *, NSString *> *)tnl_allOverrideHTTPHeaderFieldsForRequest:(id<TNLRequest>)request
                                                                                  URLRequest:(NSURLRequest *)URLRequest;

@end

NS_ASSUME_NONNULL_END

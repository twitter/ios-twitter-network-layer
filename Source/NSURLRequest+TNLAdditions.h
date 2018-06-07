//
//  NSURLRequest+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 11/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TwitterNetworkLayer/TNLHostSanitizer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURLRequest`
 */
@interface NSURLRequest (TNLAdditions)

/**
 With HTTP, a request encapsulates "what" is being sent.
 With `NSURLRequest`, however, it encapsulates a little more too, such
 as the TCP host to connect to.

 First, the DNS will be resolved for the `[NSURL host]` of `[NSURLRequest URL]`.
 That resolution will lead to an IP address to make the TCP connection with.
 The `NSURLRequest` will then be sent with a `@"Host"` header indicating the
 name of the host, which is decoupled from the actual host being connected to.
 Because of this, it can be useful to identify what the HTTP request `Host` is
 separate from the TCP connection's host.

 This method will return the `@"Host"` HTTP header field value, if populated.
 If `@"Host"` is unset, the method will return the `[NSURL host]` value since
 that is the value that the __NSURL__ stack will use instead.
 */
- (nullable NSString *)tnl_hostName;

@end

/**
 __TNL__ additions for `NSMutableURLRequest`
 */
@interface NSMutableURLRequest (TNLAdditions)

/**
 Replace the `URL.host` with a new host
 @param newHost the host to replace the existing `URL.host` with
 @param behavior the behavior on how to replace the host
 @param error if provided and result is a failure, will be populated with an error on return
 @return the result of the replacement, see `TNLHostReplacementResult`
 */
- (TNLHostReplacementResult)tnl_replaceURLHost:(NSString *)newHost
                                      behavior:(TNLHostSanitizerBehavior)behavior
                                         error:(out NSError * __nullable * __nullable)error;

@end

NS_ASSUME_NONNULL_END


//
//  NSHTTPCookieStorage+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 2/9/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSHTTPCookieStorage`
 */
@interface NSHTTPCookieStorage (TNLAdditions)

/**
 This returns a proxy that will always use the current
 `[NSHTTPCookieStorage sharedHTTPCookieStorage]` as the cookie storage.

 This is useful for setting on a `TNLRequestConfiguration` so that if the configuration is reused
 for multiple `TNLRequestOperation` instances, the `NSHTTPCookieStorage` that will be used will be
 the `[NSHTTPCookieStorage sharedHTTPCookieStorage]` at the time the `TNLRequestOperation` runs.
 This is in contrast to having the `[TNLRequestConfiguration cookieStorage]` being set to the
 `[NSHTTPCookieStorage sharedHTTPCookieStorage]` since that will not updated as the shared
 `NSHTTPCookieStorage` is updated.

 @return the shared `NSURLCredentialStorage` proxy
 */
+ (NSHTTPCookieStorage *)tnl_sharedHTTPCookieStorageProxy;

@end

NS_ASSUME_NONNULL_END

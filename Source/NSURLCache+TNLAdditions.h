//
//  NSURLCache+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 8/12/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURLCache`
 */
@interface NSURLCache (TNLAdditions)

/**
 A singleton `NSURLCache` that is impotent.

 This cache effectively does nothing, which can be desireable when you want to provide an
 `NSURLCache` to an API in order to prevent any caching.
 @return an impotent `NSURLCache`
 @discussion __See Also:__ `NSURLSessionConfiguration` and `NSURLCache`
 */
+ (NSURLCache *)tnl_impotentURLCache;

/**
 This returns a proxy that will always use the current `[NSURLCache sharedURLCache]` as the cache.

 This is useful for setting on a `TNLRequestConfiguration` so that if the configuration is reused
 for multiple `TNLRequestOperation` instances, the `NSURLCache` that will be used will be the
 `[NSURLCache sharedURLCache]` at the time the `TNLRequestOperation` run.  This is in contrast to
 having the `[TNLRequestConfiguration URLCached]` being set to the `[NSURLCache sharedURLCache]`
 since that will not updated as the shared `NSURLCache` is updated.

 @return the shared `NSURLCache` proxy
 */
+ (NSURLCache *)tnl_sharedURLCacheProxy;

@end

NS_ASSUME_NONNULL_END

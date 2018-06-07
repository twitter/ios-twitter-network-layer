//
//  NSCachedURLResponse+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 11/22/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Category for flagging cached `NSCachedURLResponse` objects as cached.
 See `NSURLResponse(TNLCacheAdditions)`
*/
@interface NSCachedURLResponse (TNLCacheAdditions)
/**
 If the target  contains an `NSHTTPURLResponse` as a `response`, the `response` will be tagged that
 it is cached by TNL.

 _TwitterNetworkLayer_ will automatically tag any cached responses that it encounters so that on
 response receipt in a subsequent operation that would hit the cache it can detect that the response
 was a cache hit so that `[TNLResponseInfo source]` will be `TNLResponseSourceLocalCache`.

 If _TNL_ is run alongside another networking stack and an `NSURLCache` can be shared, then the
 consumer should take the necessary steps to:
   1. flag any cached responses
   2. (if desired) detect cached responses with `[NSURLResponse tnl_wasCachedResponse]`.
 */
- (NSCachedURLResponse *)tnl_flaggedCachedResponse;
@end

/**
 Category for detecting if an `NSURLResponse` was flagged as being cached.
 See `NSCachedURLResponse(TNLCacheAddtions)`
 */
@interface NSURLResponse (TNLCacheAdditions)
/**
 Returns if the target `NSURLResponse` was tagged as being cached.
 See `[NSURLCachedURLResponse tnl_flaggedCachedResponse]`.
 */
- (BOOL)tnl_wasCachedResponse;
@end

NS_ASSUME_NONNULL_END

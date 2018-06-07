//
//  NSURLCredentialStorage+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 12/5/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURLCredentialStorage`
 */
@interface NSURLCredentialStorage (TNLAdditions)

/**
 This returns a proxy that will always use the current
 `[NSURLCredentialStorage sharedURLCredentialStorage]` as the credential storage.

 This is useful for setting on a `TNLRequestConfiguration` so that if the configuration is reused
 for multiple `TNLRequestOperation` instances, the `NSURLCredentialStorage` that will be used will
 be the `[NSURLCredentialStorage sharedURLCredentialStorage]` at the time the `TNLRequestOperation`
 runs.  This is in contrast to having the `[TNLRequestConfiguration URLCredentialStorage]` being
 set to the `[NSURLCredentialStorage sharedURLCredentialStorage]` since that will not updated as the
 shared `NSURLCredentialStorage` is updated.

 @return the shared `NSURLCredentialStorage` proxy
 */
+ (NSURLCredentialStorage *)tnl_sharedCredentialStorageProxy;

@end

NS_ASSUME_NONNULL_END


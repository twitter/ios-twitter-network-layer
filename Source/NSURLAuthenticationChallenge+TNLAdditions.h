//
//  NSURLAuthenticationChallenge+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 3/17/20.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//! `NSURLAuthenticationMethodOAuth` which Apple uses but doesn't expose
FOUNDATION_EXTERN NSString * const TNLNSURLAuthenticationMethodOAuth;
//! `NSURLAuthenticationMethodOAuth2` which Apple uses but doesn't expose
FOUNDATION_EXTERN NSString * const TNLNSURLAuthenticationMethodOAuth2;

//! Is the given challenge method a password challenge?
FOUNDATION_EXTERN BOOL TNLIsPasswordChallengeAuthenticationChallengeMethod(NSString * __nullable method);

/**
 __TNL__ additions for `NSURLAuthenticationChallenge`
 */
@interface NSURLAuthenticationChallenge (TNLAdditions)

/**
 @return `YES` if this challenge is an HTTP WWW Authenticate based challenge from an HTTP 401.
 @note By default, __TNL__ will reject this kind of challenge's protection space if there is no `proposedCredential`, use `TNLAuthenticationChallengeHandler` to specify a different behavior if desired.  This differs from `NSURLSession` default behavior!
 */
- (BOOL)tnl_isHTTPWWWAuthenticationChallenge;

@end

NS_ASSUME_NONNULL_END

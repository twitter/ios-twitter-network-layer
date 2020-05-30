//
//  NSURLAuthenticationChallenge+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 3/17/20.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSURLAuthenticationChallenge+TNLAdditions.h"

NSString * const TNLNSURLAuthenticationMethodOAuth = @"NSURLAuthenticationMethodOAuth";
NSString * const TNLNSURLAuthenticationMethodOAuth2 = @"NSURLAuthenticationMethodOAuth2";

BOOL TNLIsPasswordChallengeAuthenticationChallengeMethod(NSString * __nullable method)
{
    return [method isEqualToString:NSURLAuthenticationMethodHTTPBasic] ||
           [method isEqualToString:TNLNSURLAuthenticationMethodOAuth] ||
           [method isEqualToString:TNLNSURLAuthenticationMethodOAuth2];
}

@implementation NSURLAuthenticationChallenge (TNLAdditions)

- (BOOL)tnl_isHTTPWWWAuthenticationChallenge
{
    // Must be an HTTP response
    NSHTTPURLResponse *failureResponse = (id)self.failureResponse;
    if (![failureResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }

    // Must be an HTTP 401
    if (401 != failureResponse.statusCode) {
        return NO;
    }

    NSURLProtectionSpace *protectionSpace = self.protectionSpace;

    // Must be fore the `http` or `https` protocols
    if (![protectionSpace.protocol isEqualToString:NSURLProtectionSpaceHTTPS] && ![protectionSpace.proxyType isEqualToString:NSURLProtectionSpaceHTTP]) {
        return NO;
    }

    // Uncomment to log WWW-Authenticate header for debugging
//#if DEBUG
//    NSLog(@"WWW-Authenticate: %@", [failureResponse valueForHTTPHeaderField:@"WWW-Authenticate"]);
//#endif

    // Must have an auth `realm`
    if (!protectionSpace.realm) {
        return NO;
    }

    NSString * method = protectionSpace.authenticationMethod;

    // Password auth challenge
    if (TNLIsPasswordChallengeAuthenticationChallengeMethod(method)) {
        return YES;
    }

    // other HTTP challenge, maybe digest?
    return NO;
}

@end

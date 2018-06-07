//
//  TNLRequestRedirecter.h
//  TwitterNetworkLayer
//
//  Created on 2/9/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TNLRequest;
@class TNLRequestOperation;

//! Completion block for `TNLRequestRedirecter` callback
typedef void(^TNLRequestRedirectCompletionBlock)(id<TNLRequest> __nullable finalToRequest);

/**
 The delegate protocol that is used for dynamically dealing with redirection on a `TNLRequestOperation`

 If the `TNLRequestRedirecter` requires independent threading from the other delegate objects, it should dispatch_async to the queue of its choosing since the `[TNLRequestDelegate tnl_delegateQueueForRequestOperation:]` is shared between all delegate objects.
 */
@protocol TNLRequestRedirecter <NSObject>

@optional

/**
 Callback to dynamically decide how to deal with a redirect.
 Use this in conjuction with `[TNLRequestConfiguration redirectPolicy]` set to
 `TNLRequestRedirectPolicyUseCallback` to add more control to redirect behavior.

 This callback is executed from `[TNLRequestDelegate delegateQueue]` if defined, or an internal
 background queue if not defined.

 @param op              The operation that will redirect
 @param response        The `NSHTTPURLResponse` that is triggering the redirect
 @param request         The originating `NSURLRequest`
 @param toRequest       The triggered redirect `NSURLRequest`
 @param completionBlock The completion block to call with either 1) `nil` to not redirect,
 2) the unchanged _toRequest_ to permit the redirect, or 3) a modified redirect to perform
 (can be an `NSURLRequest` or a hydrated `TNLRequest`)
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
     willRedirectFromRequest:(NSURLRequest<TNLRequest> *)request
                withResponse:(NSHTTPURLResponse *)response
                   toRequest:(NSURLRequest<TNLRequest> *)toRequest
                  completion:(TNLRequestRedirectCompletionBlock)completionBlock;

@end

NS_ASSUME_NONNULL_END

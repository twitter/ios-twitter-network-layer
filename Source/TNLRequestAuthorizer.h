//
//  TNLRequestAuthorizer.h
//  TwitterNetworkLayer
//
//  Created on 8/14/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLRequestOperation;
@protocol TNLRequest;

//! completion block for `TNLRequestAuthorizer` callback
typedef void(^TNLAuthorizeCompletionBlock)(NSString * __nullable authorizationHeader,
                                           NSError * __nullable error);

/**
 The delegate protocol that authorizes `TNLRequestOperation`s.

 If the `TNLRequestAuthorizer` requires independent threading from the other delegate objects,
 it should `dispatch_async` to the queue of its choosing since the
 `[TNLRequestDelegate tnl_delegateQueueForRequestOperation:]` is shared between all delegate objects.
 */
@protocol TNLRequestAuthorizer <NSObject>

@optional

/**
 Authorize the given request to produce an `Authorization` headers (optional)

 By default, the `Authorization` HTTP header will not be modified.
 Provide the completion block with `nil` to leave the `Authorization` HTTP header.
 Provide an empty string to clear the `Authorization` HTTP header.
 Provide a string to set the `Authorization` HTTP header.

 @param op              The `TNLRequestOperation` that has been challenged
 @param URLRequest      The `NSURLRequest` to authorize (hydrated from the _originalRequest_)
 @param completion      The completion block to call to complete the authorization
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
         authorizeURLRequest:(NSURLRequest *)URLRequest
                  completion:(TNLAuthorizeCompletionBlock)completion;

@end

NS_ASSUME_NONNULL_END

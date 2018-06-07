//
//  TAPIRequestManager.h
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import "TAPIRequest.h"
#import "TAPIResponse.h"

typedef void(^TAPIRequestCompletionBlock)(__kindof TAPIResponse *response);

typedef void(^TAPILoginAccessCompletionBlock)(NSString *accessToken, NSString *accessSecret);
typedef void(^TAPILoginAccessBlock)(TAPILoginAccessCompletionBlock completion);
typedef void(^TAPILoginCompletionBlock)(BOOL loginSucceeded);

@interface TAPIClient : NSObject <TNLRequestAuthorizer, TNLRequestHydrater>

@property (atomic, copy) NSString *oauthConsumerKey;
@property (atomic, copy) NSString *oauthConsumerSecret;
@property (atomic, copy) TAPILoginAccessBlock loginAccessBlock;

+ (instancetype)sharedInstance;

// explicitely trigger login
- (NSOperation *)triggerLogin:(TAPILoginCompletionBlock)loginBlock;

// triggers login as a dependency
- (TNLRequestOperation *)startRequest:(TAPIRequest *)request
                           completion:(TAPIRequestCompletionBlock)completion;

- (TNLRequestOperation *)startRequest:(TAPIRequest *)request
                             delegate:(id<TNLRequestDelegate>)delegate;

@end

@interface TAPIClient (Auth_Hydration)

- (void)tnl_requestOperation:(TNLRequestOperation *)op
              hydrateRequest:(TAPIRequest *)request
                  completion:(TNLRequestHydrateCompletionBlock)complete;

- (void)tnl_requestOperation:(TNLRequestOperation *)op
         authorizeURLRequest:(NSURLRequest *)URLRequest
                  completion:(TNLAuthorizeCompletionBlock)completion;

@end

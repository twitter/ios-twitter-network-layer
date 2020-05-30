//
//  TAPIRequest.h
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import "TAPIModel.h"

extern NSString * const TAPIRequestDomainDefault;
extern NSString * const TAPIRequestVersion1_1;
#define TAPIRequestVersionDefault TAPIRequestVersion1_1

@protocol TAPIUndoableRequest <NSObject>
@property (nonatomic, readonly, getter=isUndo) BOOL undo;
@end

@interface TAPIRequest : NSObject <TNLRequest>

- (NSString *)baseURLString; // URL strings from scheme, domain, version and endpoint (no parameters)
- (NSURL *)URL; // composed of baseURLString (and parameters if not a POST)
- (NSData *)HTTPBody; // composed of parameters is POST (otherwise nil)
- (TNLParameterCollection *)parameters; // URL parameters, unless POST, then part of the body

// Methods to override

- (NSString *)scheme; // default == @"https"
- (NSString *)domain; // default == TAPIRequestDomainDefault
- (NSString *)version; // default == TAPIRequestVersionDefault

- (NSString *)endpoint; // default == nil, must override

- (TNLHTTPMethod)HTTPMethodValue; // default == TNLHTTPMethodGET

- (NSDictionary *)allHTTPHeaderFields NS_REQUIRES_SUPER;
- (void)prepareParameters:(TNLMutableParameterCollection *)params NS_REQUIRES_SUPER;

// Config

+ (Class)responseClass; // default == Nil (which will result in TAPIResponse), must return a `Class` that subclasses `TAPIResponse`
+ (TNLRequestConfiguration *)configuration;
+ (id<TNLRequestRetryPolicyProvider>)retryPolicyProvider;

@end

@interface TAPIRetriableRequest : TAPIRequest
@end

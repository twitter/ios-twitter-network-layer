//
//  TNLPseudoURLProtocol.h
//  TwitterNetworkLayer
//
//  Created on 10/29/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const TNLPseudoURLProtocolErrorDomain;

@class TNLPseudoURLResponseConfig;

/**
 TNLPseudoURLProtocol

 An `NSURLProtocol` subclass used for faking responses to requests.

 Set up by registering an origin with a given `NSHTTPURLResponse`, `TNLPseudoURLResponseConfig` (optional)
 and `NSData` (optional).  The protocol will kick in whenever a request matching the registered
 origin is requested (as long as the protocol has been registered appropriately).
 */
@interface TNLPseudoURLProtocol : NSURLProtocol

/**
 Register an endpoint to support with `TNLPseudoURLProtocol`

 @param response        the HTTP Response to use when the origin is encountered
 @param config          the config to use for customizing the response behavior
 @param body            the body (or `nil`) to use when the origin is encountered
 @param endpoint        the endpoint to handle
 */
+ (void)registerURLResponse:(NSHTTPURLResponse *)response
                       body:(nullable NSData *)body
                     config:(nullable TNLPseudoURLResponseConfig *)config
               withEndpoint:(NSURL *)endpoint;

/**
 See `registerURLResponse:body:config:withEndpoint:`
 */
+ (void)registerURLResponse:(NSHTTPURLResponse *)response
                       body:(nullable NSData *)body
               withEndpoint:(NSURL *)endpoint;

/**
 Unregister an endpoint.  __See Also__ `registerURLResponse:body:withEndpoint:`
 */
+ (void)unregisterEndpoint:(NSURL *)endpoint;

/**
 Unregisert all endpoints.
 */
+ (void)unregisterAllEndpoints;

/**
 Check if an endpoint is registered.
 Goes through synchronization, so after this returns the _endpoint_ could async end up [un]registered.
 */
+ (BOOL)isEndpointRegistered:(NSURL *)endpoint;

@end

//! Behavior for how the pseudo protocol should handle an observed redirect
typedef NS_ENUM(NSUInteger, TNLPseudoURLProtocolRedirectBehavior) {
    /** Follow redirect when `Location` header field is provided */
    TNLPseudoURLProtocolRedirectBehaviorFollowLocation = 0,
    /** Return the 3xx HTTP response, don't follow the redirect */
    TNLPseudoURLProtocolRedirectBehaviorDontFollowLocation = 1,
    /** Follow redirect when `Location` header field's value is registered with a response too, otherwise return the 3xx response */
    TNLPseudoURLProtocolRedirectBehaviorFollowLocationIfRedirectResponseIsRegistered = 2,
};

/**
 The configuration for how the response should behave when registering a pseudo-URLResponse with
 `TNLPseudoURLProtocol`
 */
@interface TNLPseudoURLResponseConfig : NSObject <NSCopying>

/**
 bits per second
 `0` == unlimited
 */
@property (nonatomic) uint64_t bps;
/**
 milliseconds of latency
 (time between each response chunk of data)
 */
@property (nonatomic) uint64_t latency;
/**
 milliseconds of delay
 (time before response chunks of data start being "received")
 */
@property (nonatomic) uint64_t delay;
/**
 the error to simulate as a failure
 `nil` == no error
 */
@property (nonatomic, nullable) NSError *failureError;
/**
 The HTTP status code to override with
 `0` == don't override the status code
 */
@property (nonatomic) NSInteger statusCode;
/**
 Whether a range of the response data can be returned (which would convert a `200` to a `206` if a
 range is returned.
 `YES` == default
 */
@property (nonatomic) BOOL canProvideRange;
/**
 When returning a `Range`, the `If-Range` header can be checked.
 `nil` == any `If-Range` value can match
 `@""` == no `If-Range` values are permitted to match
 otherwise == the given string will be matched with `isEqualToString:`
 */
@property (nonatomic, copy, nullable) NSString *stringForIfRange;
/**
 Redirect behavior.
 `TNLPseudoURLProtocolRedirectBehaviorFollowLocation` == default
 */
@property (nonatomic) TNLPseudoURLProtocolRedirectBehavior redirectBehavior;

/**
 Any additional headers that the `TNLPseudoURLProtocol` should coerse the request to have
 */
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *extraRequestHeaders;

@end

NS_ASSUME_NONNULL_END


//
//  TNLBackoff.h
//  TwitterNetworkLayer
//
//  Created on 3/31/20.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLHTTP.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark Constants

//! Default "Backoff" value for the `TNLSimpleBackoffBehaviorProvider`
FOUNDATION_EXTERN const NSTimeInterval TNLSimpleRetryAfterBackoffValueDefault;
//! Minimum "Backoff" value for the `TNLSimpleBackoffBehaviorProvider`
FOUNDATION_EXTERN const NSTimeInterval TNLSimpleRetryAfterBackoffValueMinimum;
//! Maximum "Backoff" value before reverting to use the `Default` value for the `TNLSimpleBackoffBehaviorProvider`
FOUNDATION_EXTERN const NSTimeInterval TNLSimpleRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway;

#pragma mark Structs

//! `TNLBackoffBehavior` struct to encapsulate the settings that control "Backoff" behavior
typedef struct TNLBackoffBehavior_T {
    /**
     The "Backoff" duration...
     how long all future enqueued matching requests will wait before any fire (based on the `TNLGlobalConfigurationBackoffMode`).

     If `0.0` or less, no "backoff" will happen.
     */
    NSTimeInterval backoffDuration;
    /**
     The "Serialize Requests" duration...
     how long requests being enqueued will continue to execute serially after the backoff signal was
     encountered (based on the `TNLGlobalConfigurationBackoffMode`).

     Once this duration expires (or if `<= 0.0`),
     serialization of requests will continue as long as there are requests in the queue that were serialized
     (which will continue to enqueue serially while there is an outstanding "backoff" duration running).
     Requests being sent after both "Serialize Requests" and "Backoff" durations have expired will
     wait for the existing serially enqueued requests to complete before executing concurrently.

     Default == `0.0`
     */
    NSTimeInterval serializeDuration;
    /**
     The minimum amount of time to elapse between the _start_ of each serial request.
     This does not indicate the duration between serial requests...that will vary based on the duration of any given request's duration.

     Default == `0.0`
     */
    NSTimeInterval serialDelayDuration;
} TNLBackoffBehavior;

//! Make a `TNLBackoffBehavior`
NS_INLINE TNLBackoffBehavior TNLBackoffBehaviorMake(NSTimeInterval backoff,
                                                    NSTimeInterval serialize,
                                                    NSTimeInterval delay)
{
    TNLBackoffBehavior behavior;
    behavior.backoffDuration = backoff;
    behavior.serializeDuration = serialize;
    behavior.serialDelayDuration = delay;
    return behavior;
}

//! Make a disabled `TNLBackoffBehavior`
#define TNLBackoffBehaviorDisabled() TNLBackoffBehaviorMake(0, 0, 0)

#pragma mark Protocols

/**
 The `TNLBackoffBehaviorProvider` protocol provides the callback for selecting the
 `TNLBackoffBehavior` for an encountered backoff signal.

 Due to opaque nature of signaling backoffs, only the _URL_ and _headers_ are provided.
 */
@protocol TNLBackoffBehaviorProvider <NSObject>

/**
 The callback to provide the backoff behavior for a `503` _Service Unavailable_ signal.
 @param URL the `NSURL` of the request that raised the signal.
 @param headers the HTTP response headers of the request that raised the signal.
 @return the `TNLBackoffBehavior` for how to backoff (or not).
 */
- (TNLBackoffBehavior)tnl_backoffBehaviorForURL:(NSURL *)URL
                                responseHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers;

@end

/**
 The `TNLBackoffSignaler` protocol provides an abstraction point for deciding if a backoff signal should be raised or not.
 */
@protocol TNLBackoffSignaler <NSObject>

/**
 The callback to check if the given response information should signal a backoff.
 @param URL the `NSURL` of the request that might raise the signal.
 @param host the (optional) host override for the request that might raise the signal.
 @param statusCode the `TNLHTTPStatusCode` of the response that might raise the signal.
 @param responseHeaders the HTTP headers of the response that might raise the signal.
 @return `YES` if backoff signal should be raised, `NO` otherwise.
 */
- (BOOL)tnl_shouldSignalBackoffForURL:(NSURL *)URL
                                 host:(nullable NSString *)host
                           statusCode:(TNLHTTPStatusCode)statusCode
                      responseHeaders:(nullable NSDictionary<NSString *, NSString *> *)responseHeaders;

@end

#pragma mark Simple Concrete Classes (Default Implementations)

/**
 A simple `TNLBackoffBehaviorProvider` implemenation.

 The behavior's `backoffDuration` will be set to the `"Retry-After"` duration
 (computed from the value either being a date or a duration in seconds).
 If no `"Retry-After"` header is present, `TNLSimpleRetryAfterBackoffValueDefault` will be used.
 If the duration would be greater than `TNLSimpleRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway`,
 then `TNLSimpleRetryAfterBackoffValueDefault` will be used.
 The duration will have a minimum value of `TNLSimpleRetryAfterBackoffValueMinimum`.

 The default **TNL** behavior provider is an instance of this class with `serializeDuration` set to `0.0`.
 */
@interface TNLSimpleBackoffBehaviorProvider : NSObject <TNLBackoffBehaviorProvider>

/**
 The `serializeDuration` for any `TNLBackoffBehavior` this provider would return.
 Default value == `0.0`
 */
@property (atomic) NSTimeInterval serializeDuration;

/**
 The `serialDelayDuration` for any `TNLBackoffBehavior` this provider would return.
 Default value == `0.0`
 */
@property (atomic) NSTimeInterval serialDelayDuration;

@end

/**
 A simple `TNLBackoffSignaler` implementation.

 Simply triggers the backoff signal if the _statusCode_ is `503` _Service Unavailable_.
 */
@interface TNLSimpleBackoffSignaler : NSObject <TNLBackoffSignaler>
@end

NS_ASSUME_NONNULL_END

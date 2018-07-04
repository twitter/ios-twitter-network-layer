//
//  TNLNetwork.h
//  TwitterNetworkLayer
//
//  Created on 9/15/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Constants

FOUNDATION_EXTERN NSString * const TNLNetworkExecutingNetworkConnectionsDidUpdateNotification;
FOUNDATION_EXTERN NSString * const TNLNetworkExecutingNetworkConnectionsExecutingKey; // NSNumber (BOOL) - YES indicates there are executing connections, NO indicates there are no executing connections
FOUNDATION_EXTERN NSString * const TNLNetworkDidSpinUpSessionNotification;
FOUNDATION_EXTERN NSString * const TNLNetworkWillWindDownSessionNotification;
FOUNDATION_EXTERN NSString * const TNLNetworkSessionIdentifierKey;

/**

 # TNLNetwork, a static class for Network methods

 ## Manually Increment/Decrement Executing Connections

 See `[TNLNetwork incrementExecutingNetworkConnections]` and `[TNLNetwork decrementExecutingNetworkConnections]`

 ## Pattern for updating network activity indicator

    @implementation MyCustomApplicationDelegate : NSObject <NSApplicationDelegate>
    // ...
    - (instancetype)init
    {
        if (self = [super init]) {
            // ...
            NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
            [nc addObserver:self
                   selector:@selector(_networkExecutionsUpdated:)
                       name:TNLNetworkExecutingNetworkConnectionsDidUpdateNotification
                     object:nil];
            // ...
        }
        return self;
    }
    // ...
    - (void)_networkExecutionsUpdated:(NSNotification *)note
    {
        NSNumber *isOn;
        isOn = note.userInfo[TNLNetworkExecutingNetworkConnectionsExecutingKey];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL on = [isOn boolValue];
            [UIApplication sharedApplication].networkActivityIndicatorVisible = on;
        });
    }
    // ...
    - (void)applicationDidBecomeActive:(UIApplication *)application
    {
        BOOL on = [TNLNetwork hasExecutingNetworkConnections];
        application.networkActivityIndicatorVisible = on;
    }
    // ...
    @end

 */
NS_ROOT_CLASS
@interface TNLNetwork

/**
 Increment the number of network connections executing.

 When the number increments from `0` to `1`,
 `TNLNetworkExecutingNetworkConnectionsDidUpdateNotification` will be fired with
 `TNLNetworkExecutingNetworkConnectionsExecutingKey` in the _userInfo_ set to `@YES`

 `TNLRequestOperationQueue` instances automatically manages the increment and decrement for
 `TNLRequestOperation`s enqueued to them.
 If you run non-__TNL__ networking operations (like `WKWebView`) you should manage the
 increment/decrement yourself.

 See `[TNLNetwork decrementExecutingNetworkConnections]`
 */
+ (void)incrementExecutingNetworkConnections;

/**
 Decrement then number of network connections executing.

 When the number decrements to `0`, `TNLNetworkExecutingNetworkConnectionsDidUpdateNotification`
 will be fired with `TNLNetworkExecutingNetworkConnectionsExecutingKey` in the _userInfo_ set to `@NO`

 `TNLRequestOperationQueue` instances automatically manages the increment and decrement for
 `TNLRequestOperation`s enqueued to them.
 If you run non-__TNL__ networking operations (like `WKWebView`) you should manage the
 increment/decrement yourself.

 See `[TNLNetwork incrementExecutingNetworkConnections]`
 */
+ (void)decrementExecutingNetworkConnections;

/**
 Retrieve whether or not there are running network connections executing.

 See `[TNLNetwork incrementExecutingNetworkConnections]` and `[TNLNetwork decrementExecutingNetworkConnections]`
 */
+ (BOOL)hasExecutingNetworkConnections;

/**
 Provide a signal to __TNL__ that a service unavailable HTTP status code was encountered.
 This will be used for backing off requests (within __TNL__) to the provided _URL_ `host`.
 */
+ (void)serviceUnavailableEncounteredForURL:(NSURL *)URL
                            retryAfterDelay:(NSTimeInterval)delay;

/**
 Provide a signal to __TNL__ when an HTTP response was encountered.
 If the `statusCode` is `TNLHTTPStatusCodeServiceUnavailable`, then
 `serviceUnavailableEncounteredForHost:retryAfterDelay:` will be called with the parsed
 `"Retry-After"` value.
 */
+ (void)HTTPURLResponseEncounteredOutsideOfTNL:(NSHTTPURLResponse *)response;

/**
 Apply backoff dependencies to a given `NSOperation` (from outside of __TNL__) that depends on a
 service unavailable backoff be resolved before it should start.
 */
+ (void)applyServiceUnavailableBackoffDependenciesToOperation:(NSOperation *)op
                                                      withURL:(NSURL *)URL
                                            isLongPollRequest:(BOOL)isLongPoll;

@end

NS_ASSUME_NONNULL_END

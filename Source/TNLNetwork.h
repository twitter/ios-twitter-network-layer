//
//  TNLNetwork.h
//  TwitterNetworkLayer
//
//  Created on 9/15/14.
//  Copyright © 2020 Twitter. All rights reserved.
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
 Provide a signal to __TNL__ that a backoff signaling HTTP response was encountered.
 This will be used for backing off requests (within __TNL__) to the provided _URL_ `host` (or provided _host_ if a different host from the _URL_ is preferred).
 @param URL the `NSURL` of the backoff signaling response
 @param host the optional host to use instead of the _URL_ `host`
 @param headers the HTTP headers in the response accompanying the backoff signal
 */
+ (void)backoffSignalEncounteredForURL:(NSURL *)URL
                                  host:(nullable NSString *)host
                   responseHTTPHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers;

/**
 Provide a signal to __TNL__ when an HTTP response was encountered.
 Checks `[TNLGlobalConfiguration backoffSignaler]` and if backoff is signaled,
 then `backoffSignalEncounteredForHost:host:responseHTTPHeaders:` will be called with the response's
 `allHeaderFields`.
 @param response the `NSHTTPURLResponse` to examine
 @param host the optional host to use instead of the _response_ `URL.host`
 */
+ (void)HTTPURLResponseEncounteredOutsideOfTNL:(NSHTTPURLResponse *)response
                                          host:(nullable NSString *)host;

/**
 Apply backoff dependencies to a given `NSOperation` (from outside of __TNL__) that depends on a
 backoff be resolved before it should start.
 @param op the `NSOperation` to apply dependencies to
 @param URL the `NSURL` of the operation
 @param host the optional host for the operation (will be used instead of the `host` from the given _URL_ for keying off of)
 @param isLongPoll whether or not the operation is a long polling operation
 */
+ (void)applyBackoffDependenciesToOperation:(NSOperation *)op
                                    withURL:(NSURL *)URL
                                       host:(nullable NSString *)host
                          isLongPollRequest:(BOOL)isLongPoll;

@end

NS_ASSUME_NONNULL_END

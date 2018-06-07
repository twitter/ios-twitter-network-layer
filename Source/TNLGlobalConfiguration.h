//
//  TNLGlobalConfiguration.h
//  TwitterNetworkLayer
//
//  Created on 11/21/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLPriority.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TNLAuthenticationChallengeHandler;
@protocol TNLHTTPHeaderProvider;
@protocol TNLHostSanitizer;
@protocol TNLLogger;
@protocol TNLNetworkObserver;
@class TNLRequestOperation;
@class TNLCommunicationAgent;

///! The default duration for the request operation callback timeout
FOUNDATION_EXTERN const NSTimeInterval TNLGlobalConfigurationRequestOperationCallbackTimeoutDefault;

/**
 The mode for how idle timeouts are used in *TNL*
 */
typedef NS_ENUM(NSInteger, TNLGlobalConfigurationIdleTimeoutMode)
{
    /** Don't use the idle timeout for request operations */
    TNLGlobalConfigurationIdleTimeoutModeDisabled = 0,
    /** Do use the idle timeout, but only after we get our first callback from NSURL stack */
    TNLGlobalConfigurationIdleTimeoutModeEnabledExcludingInitialConnection = 1,
    /**
     Do use the idle timeout, including while we wait for the first callback from NSURL stack
     WARNING: imposing an idle timeout that affects connection time is often a bad idea and will yield more failures with devices that have difficulty connecting
     */
    TNLGlobalConfigurationIdleTimeoutModeEnabledIncludingInitialConnection = 2,

    /** Default idle timeout mode */
    TNLGlobalConfigurationIdleTimeoutModeDefault = TNLGlobalConfigurationIdleTimeoutModeEnabledExcludingInitialConnection,
};

/**
`TNLGlobalConfigurationServiceUnavailableBackoffMode` enumerates the modes for how to handle
 service unavailable (503) responses with backoff behavior. The backoff behavior is to observe the
 `Retry-After` of the last matching request receiving a service unavailable response (503) before
 executing backed off requests one at a time until either A) all requests are flushed or B) another
 503 is encountered restarting the backoff.

 https://docs.google.com/document/d/1Gs3P0aSuEYMjvCfKkolRseS4Fnm3p%5FVDQwbu4LNCRKA/edit?usp=sharing
 */
typedef NS_ENUM(NSInteger, TNLGlobalConfigurationServiceUnavailableBackoffMode)
{
    /**
     Don't automatically back off when 503s are encountered
     */
    TNLGlobalConfigurationServiceUnavailableBackoffModeDisabled = 0,
    /**
     Automatically back off requests when the `host` matches prior requests that saw a 503.
     */
    TNLGlobalConfigurationServiceUnavailableBackoffModeKeyOffHost = 1,
    /**
     Automatically back off requests when the `host` and `path` match prior requests that saw a 503.
     */
    TNLGlobalConfigurationServiceUnavailableBackoffModeKeyOffHostAndPath = 2,
};

/**
 `TNLGlobalConfiguration` is where the settings that affect all of TNL are maintained.
 Configure `[TNLGlobalConfiguration sharedInstance]` early on during app startup before networking
 starts.
 */
@interface TNLGlobalConfiguration : NSObject

/**
 The version of the Twitter Network Layer library.

 Only returns the major and minor version: e.g. `@"1.0"`
 @return a string representing the TNL version.
 */
+ (NSString *)version;

/**
 Singleton accessor
 */
+ (instancetype)sharedInstance;

/** init is unavailable */
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

#pragma mark Delegates

/**
 The `TNLHostSanitizer` that is globally applied to all `TNLRequestOperation`s.

 __See Also:__ `TNLHostSanitizer`
 */
@property (atomic, strong, nullable) id<TNLHostSanitizer> hostSanitizer;

/**
 Add a `TNLNetworkObserver` for getting callbacks for all `TNLRequestOperationQueue` instances.
 Redundantly adding an _observer_ that is already observing will be a no-op.
 __See Also:__ `removeNetworkObserver:`, `TNLNetworkObserver` and `[TNLRequestOperationQueue networkObserver]`
 */
- (void)addNetworkObserver:(id<TNLNetworkObserver>)observer;

/**
 Remove a `TNLNetworkObserver` that was getting callbacks for all `TNLRequestOperationQueue` instances.
 Removing an _observing_ that is not observing will be a no-op.
 __See Also:__ `addNetworkObserver:`, `TNLNetworkObserver` and `[TNLRequestOperationQueue networkObserver]`
 */
- (void)removeNetworkObserver:(id<TNLNetworkObserver>)observer;

/**
 Return all the registered network observers
 */
- (NSArray<id<TNLNetworkObserver>> *)allNetworkObservers;

/**
 Add a `TNLHTTPHeaderProvider` that is globally applied to all `TNLRequestOperation`s.
 Last added provider will win in case of a conflict in header field.

 __See Also:__ `TNLHTTPHeaderProvider`
 */
- (void)addHeaderProvider:(id<TNLHTTPHeaderProvider>)provider;

/**
 Remove a `TNLHTTPHeaderProvider` that is globally applied to all `TNLRequestOperation`s.

 __See Also:__ `TNLHTTPHeaderProvider`
 */
- (void)removeHeaderProvider:(id<TNLHTTPHeaderProvider>)provider;

/**
 Return all the registered HTTP header providers
 */
- (NSArray<id<TNLHTTPHeaderProvider>> *)allHeaderProviders;

/**
 The specified `TNLCommunicationAgent` will be used for all `TNLAttemptMetrics` to capture the best
 guess network state at attempt completion.
 Ideally, network state would be provided in task transaction metrics by Apple.
 */
@property (atomic, nullable) TNLCommunicationAgent *metricProvidingCommunicationAgent;

#pragma mark Settings

/**
 The threshold where operations above the threshold will be considered "dependencies" for all
 operations that enqueue below the threshold.

 Default == `NSIntegerMax`, which disables the feature.
 `TNLPriorityVeryHigh` is a good choice as it would require explicitely setting the operation to a
 higher value (which is out of the enum range) to enable the automatic dependency
 (such as `(NSInteger)(TNLPriorityVeryHigh + 1)`).
 */
@property (nonatomic) TNLPriority operationAutomaticDependencyPriorityThreshold;

/**
 The backoff mode when a 503 is encountered.

 Default == `TNLGlobalConfigurationServiceUnavailableBackoffModeDisabled`
 */
@property (atomic) TNLGlobalConfigurationServiceUnavailableBackoffMode serviceUnavailableBackoffMode;

#pragma mark Authentication Challenges

/**
 Register a `TNLAuthenticationChallengerHandler`.
 Callbacks to the _handler_ are made on the socket thread and will be thread safe.
 Handlers are called in the order they were registered.
 When a handler provides `NSURLSessionAuthChallengePerformDefaultHandling` as the _disposition_,
 the next handler will be tried until all handlers are exhausted and then the default behavior will
 take effect.
 */
- (void)addAuthenticationChallengeHandler:(id<TNLAuthenticationChallengeHandler>)handler;

/**
 Unregister a `TNLAuthenticationChallengerHandler`
 */
- (void)removeAuthenticationChallengeHandler:(id<TNLAuthenticationChallengeHandler>)handler;

#pragma mark Clogged Callbacks

/**
 The timeout for `TNLRequestOperation` callbacks to execute within
 (includes all `TNLRequestDelegate` callbacks and `TNLRequestRetryPolicyProvider` callbacks)

 Set to `0` or negative value to disable callback clog detection.
 Default == 10 seconds
 */
@property (nonatomic, readwrite) NSTimeInterval requestOperationCallbackTimeout;

/**
 For debugging purposes it can be useful to identify when a callback from TNL is taking too long
 (clogging execution of a `TNLRequestOperation`).
 "Clogged" callbacks will trigger an idle timeout and can be easily be missed as the actual network
 causing the timeout.
 Enable this setting to force a crash with some contextual information that indicates where the clog
 happened.

 Default == `NO`
 */
@property (atomic, readwrite) BOOL shouldForceCrashOnCloggedCallback;

#pragma mark Timeouts

/**
 Configure the how idle timeouts behave within *TNL*.

 Default == `TNLGlobalConfigurationIdleTimeoutModeDefault`
*/
@property (nonatomic, readwrite) TNLGlobalConfigurationIdleTimeoutMode idleTimeoutMode;

/**
 Configure the how "data" timeouts behave within *TNL*. Zero or negative disables the timeout.

 Default == `0.0`
 */
@property (nonatomic, readwrite) NSTimeInterval timeoutIntervalBetweenDataTransfer;

#pragma mark Runtime Config

/**
 Configure the delegate for log messages within the *TwitterNetworkLayer*

 Default == `nil`
 */
@property (atomic, readwrite, nullable) id<TNLLogger> logger;

/**
 Configure whether or not to execute asserts within the *TwitterNetworkLayer*

 Default == `YES`
 */
@property (nonatomic, readwrite, getter=areAssertsEnabled) BOOL assertsEnabled;

@end

/**
 Methods to help with debugging TNL
 */
@interface TNLGlobalConfiguration (Debugging)

/**
 All enqueued and/or running `TNLRequestOperation` operations.
 Very expensive, just use for debugging.
 */
- (NSArray<TNLRequestOperation *> *)allRequestOperations;

@end

NS_ASSUME_NONNULL_END

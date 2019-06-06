//
//  TNLRequestConfiguration.h
//  TwitterNetworkLayer
//
//  Created on 7/15/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLHTTP.h>
#import <TwitterNetworkLayer/TNLPriority.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Foreward declarations

@protocol TNLRequestRetryPolicyProvider;
@protocol TNLContentEncoder; // TNLContentCoding.h
@protocol TNLContentDecoder; // TNLContentCoding.h
@class TNLRequestOperation;
@class TNLResponse;

#pragma mark - Enums

/**
 The redirect policy for a request.  See `[TNLRequestConfiguration redirectPolicy]`.
 */
typedef NS_ENUM(NSInteger, TNLRequestRedirectPolicy) {
    /** Don't permit any redirects */
    TNLRequestRedirectPolicyDontRedirect = 0,
    /** Permit any redirects */
    TNLRequestRedirectPolicyDoRedirect,
    /** Only permit redirects to the same host */
    TNLRequestRedirectPolicyRedirectToSameHost,
    /** Defer to the `TNLRequestRedirecter`.  If callback isn't implemented, fallback to Default. */
    TNLRequestRedirectPolicyUseCallback,

    /** Default */
    TNLRequestRedirectPolicyDefault = TNLRequestRedirectPolicyDoRedirect,
};

/**
 The consumption mode for response data.  See `[TNLRequestConfiguration responseDataConsumptionMode]`.

 Note that when the consumption mode is `TNLResponseDataConsumptionModeSaveToDisk` and the execution
 mode is `TNLRequestExecutionModeBackground` it is required that the request have either no HTTP Body or,
 if a body is set, it must be as data and not as a stream or a file.

 ## enum TNLResponseDataConsumptionMode
 */
typedef NS_ENUM(NSInteger, TNLResponseDataConsumptionMode) {
    /** Drop any incoming data */
    TNLResponseDataConsumptionModeNone = 0,
    /** Persist incoming data in an `NSData` object that will be exposed by _info.data_ property of the `TNLResponse` */
    TNLResponseDataConsumptionModeStoreInMemory,
    /** Persist incoming data to a file on disk that will exposed by the _info.temporaryFile_ property of the `TNLResponse` (HTTP GET only) */
    TNLResponseDataConsumptionModeSaveToDisk,
    /** As incoming data is received, chunk that data to the `[TNLRequestEventHandler tnl_requestOperation:didReceiveData:]` callback  */
    TNLResponseDataConsumptionModeChunkToDelegateCallback,

    /** Default */
    TNLResponseDataConsumptionModeDefault = TNLResponseDataConsumptionModeStoreInMemory,
};

/**
 The execution mode for the request operation.  See `[TNLRequestConfiguration executionMode]`.

 @note `TNLRequestExecutionModeBackground` (which effectively uses a backgroud `NSURLSession`) is
 much slower than `TNLRequestExecutionModeInApp` due to the XPC involved and lower system priority.
 With smaller resources: the faster the network, the faster the network connection is, the more
 noticeable the slowdown from XPC.  WiFi broadband connections can often result in 5x slowdowns for
 smaller resources when using `TNLRequestExecutionModeBackground`.
 */
typedef NS_ENUM(NSInteger, TNLRequestExecutionMode) {
    /** Operation is executed in process */
    TNLRequestExecutionModeInApp = 0,
    /**
     Operation is executed in process AND registered with the `UIApplication` as a background task.
     @note Only applies to __iOS__ apps, otherwise it behaves exactly the same as `ModeInApp`.
     That includes Mac OS X apps and iOS Extensions.
     */
    TNLRequestExecutionModeInAppBackgroundTask = 1,
    /**
     Operation is executed in the background.
     Slower than `ModeInApp` plus has some restrictions:
       1. The operation must end up as an upload or a download.
          To qualify as an upload, the HTTP Body must be set as a file or `NSData` (streams are not supported).
          To qualify as a download, `[TNLRequestConfiguration responseDataConsumptionMode]` must set
          to `TNLResponseDataConsumptionModeSaveToDisk`.
       2. When `[TNLRequestConfiguration responseDataConsumptionMode]` is set to
          `TNLResponseDataConsumptionModeSaveToDisk`, the request must have either no HTTP Body or,
          if a body is set, it must be set as data and not as a stream or a file.
          Simplest is to avoid having a background request that both uploads and downloads at the same time.
     */
    TNLRequestExecutionModeBackground = 8,

    /** Default */
    TNLRequestExecutionModeDefault = TNLRequestExecutionModeInApp,
};

/**
 The options for what `NSURLProtocol`s to use.  See `[NSURLSessionConfiguration protocols]`.
 */
typedef NS_OPTIONS(NSInteger, TNLRequestProtocolOptions) {
    /** No custom protocols, just OS defaults */
    TNLRequestProtocolOptionsNone = 0,

    /** Used to be for CocoaSPDY, which has been deprecated - now held in reserve for compatibility */
    TNLRequestProtocolOption_RESERVED0 = (1 << 0),

    /**
     Use the special pseudo-protocol.
     This protocol can be used for faking requests and responses and their behavior.
     */
    TNLRequestProtocolOptionPseudo = (1 << 1),

    /** The default options, which is just `TNLRequestProtocolOptionsNone` */
    TNLRequestProtocolOptionsDefault = TNLRequestProtocolOptionsNone,
};

/**
 Options for how a request operation should behave when waiting for connectivity.
 Does not apply to background request operations.
 Waiting for connectivity will wait indefinitely until connectivity or a timeout occurs.
 See `[NSURLSessionConfiguration waitsForConnectivity]`.
 */
typedef NS_OPTIONS(NSInteger, TNLRequestConnectivityOptions) {
    /** No options.  Fail if no connectivity and depend on retry policy. */
    TNLRequestConnectivityOptionsNone = 0,

    /** Wait for connectivity always */
    TNLRequestConnectivityOptionWaitForConnectivity = (1 << 0),

    /**
     Wait for connectivity if retry policy is present.
     No-op if `TNLRequestConnectivityOptionWaitForConnectivity` is also set.
     */
    TNLRequestConnectivityOptionWaitForConnectivityWhenRetryPolicyProvided = (1 << 1),

    /**
     Invalidate attempt timeout when waiting for connectivity encountered.
     No-op if the other options don't enable waiting for connectivity.
     */
    TNLRequestConnectivityOptionInvalidateAttemptTimeoutWhenWaitForConnectivityTriggered = (1 << 2),

    /**
     Suspend the attempt timeout while waiting for connectivity, resuming when connectivity returns.
     No-op if `TNLRequestConnectivityOptionInvalidateAttemptTimeoutWhenWaitForConnectivityTriggered` is also set.
     TODO: there is no event from NSURLSession when a task continues upon connectivity, so this is
           feature is out of reach right now.
     */
    // TNLRequestConnectivityOptionSuspendAttemptTimeoutDuringWaitForConnectivity = (1 << 3),

    /** Default */
    TNLRequestConnectivityOptionsDefault = TNLRequestConnectivityOptionsNone,
};

/**
 The algorithm to compute a hash for the response body
 */
typedef NS_ENUM(NSInteger, TNLResponseHashComputeAlgorithm) {
    TNLResponseHashComputeAlgorithmNone = 0,
    TNLResponseHashComputeAlgorithmMD2 __attribute__((deprecated)) = 'md_2',
    TNLResponseHashComputeAlgorithmMD4 __attribute__((deprecated)) = 'md_4',
    TNLResponseHashComputeAlgorithmMD5 __attribute__((deprecated)) = 'md_5',
    TNLResponseHashComputeAlgorithmSHA1 = 'sha1',
    TNLResponseHashComputeAlgorithmSHA256 = 's256',
    TNLResponseHashComputeAlgorithmSHA512 = 's512',
};

/**
 The expected anatomy of how a request will break down
 */
typedef NS_ENUM(NSInteger, TNLRequestAnatomy) {
    TNLRequestAnatomySmallRequestSmallResponse, // GET w/ small response
    TNLRequestAnatomySmallRequestLargeResponse, // JSON or XML response
    TNLRequestAnatomyLargeRequestSmallResponse, // JSON or XML request
    TNLRequestAnatomyLargeRequestLargeResponse, // JSON or XML request & response
    TNLRequestAnatomyVeryLargeRequestSmallResponse, // media request
    TNLRequestAnatomySmallRequestVeryLargeResponse, // media response
    TNLRequestAnatomySmallRequestStreamingResponse, // response is a stream

    TNLRequestAnatomyDefault = TNLRequestAnatomySmallRequestLargeResponse,
};

#pragma mark - Functions

//! Compute a reasonable interval for deferring based on a given `TNLPriority`
FOUNDATION_EXTERN NSTimeInterval TNLDeferrableIntervalForPriority(TNLPriority pri) __attribute__((const));

#pragma mark - Configuration Class

/**
 The configuration to associate with a `TNLRequestOperation`

 __See also:__ `TNLMutableRequestConfiguration`, `TNLRequestOperation`, `TNLRequestOperationQueue`
 and `TNLRequestConfiguration`

 # TNLDeferrableIntervalForPriority

 Function to compute a default `[TNLRequestConfiguration deferrableInterval]` from a `TNLPriority`

    FOUNDATION_EXTERN NSTimeInterval TNLDeferrableIntervalForPriority(TNLPriority pri) __attribute__((const));

 */
@interface TNLRequestConfiguration : NSObject <NSCopying, NSMutableCopying>
{
@protected
    // TNL settings
    id<TNLRequestRetryPolicyProvider> _retryPolicyProvider;
    id<TNLContentEncoder> _contentEncoder;
    NSArray<id<TNLContentDecoder>> *_additionalContentDecoders;

    // NSURLSessionConfiguration settings
    NSString *_sharedContainerIdentifier;
    NSURLCredentialStorage *_URLCredentialStorage;
    NSURLCache *_URLCache;
    NSHTTPCookieStorage *_cookieStorage;

    // ivar struct
    struct {

        // TNL settings
        TNLRequestExecutionMode executionMode:8;
        TNLRequestRedirectPolicy redirectPolicy:8;
        TNLResponseDataConsumptionMode responseDataConsumptionMode:8;
        TNLRequestProtocolOptions protocolOptions:8;
        TNLRequestConnectivityOptions connectivityOptions:8;
        TNLResponseHashComputeAlgorithm responseComputeHashAlgorithm;

        // Timeout settings
        NSTimeInterval idleTimeout;
        NSTimeInterval attemptTimeout;
        NSTimeInterval operationTimeout;
        NSTimeInterval deferrableInterval;

        // NSURLSessionConfiguration settings
        NSURLRequestCachePolicy cachePolicy:8;
        NSURLRequestNetworkServiceType networkServiceType:8;
        NSHTTPCookieAcceptPolicy cookieAcceptPolicy:4;
        NSInteger /*NSURLSessionMultipathServiceType*/ multipathServiceType:4;

        // TNL BOOLs
        BOOL contributeToExecutingNetworkConnectionsCount:1;
        BOOL skipHostSanitization:1;

        // NSURLSessionConfiguration BOOLs
        BOOL allowsCellularAccess:1;
        BOOL discretionary:1;
        BOOL shouldLaunchAppForBackgroundEvents:1;
        BOOL shouldSetCookies:1;

    } _ivars;
}

/**
 The request operation mode

 Default is `TNLRequestExecutionModeDefault`
 @discussion __See Also__ `TNLRequestExecutionMode`
 */
@property (nonatomic, readonly) TNLRequestExecutionMode executionMode;

/**
 The request redirect policy

 Default is `TNLRequestRedirectPolicyDefault`
 @discussion __See Also__ `TNLRequestRedirectPolicy`
 */
@property (nonatomic, readonly) TNLRequestRedirectPolicy redirectPolicy;

/**
 The response data consumption mode

 Default is `TNLResponseDataConsumptionModeDefault`
 @discussion __See Also__ `TNLResponseDataConsumptionMode`
 */
@property (nonatomic, readonly) TNLResponseDataConsumptionMode responseDataConsumptionMode;

/**
 The protocol options to use

 Default is `TNLRequestProtocolOptionsDefault` (i.e. `TNLRequestProtocolOptionsNone`)
 @discussion __See Also__ `TNLRequestProtocolOptions`
 */
@property (nonatomic, readonly) TNLRequestProtocolOptions protocolOptions;

/**
 The options for how to handle waiting for connectivity.

 Default is `TNLRequestConnectivityOptionsDefault` (fail instead of waiting for connectivity)
 Requires iOS 11, macOS 10.13
 */
@property (nonatomic, readonly) TNLRequestConnectivityOptions connectivityOptions;

/**
 Whether the request operation should contribute to the
 `[TNLNetwork incrementExecutingNetworkConnections]` and
 `[TNLNetwork decrementExecutingNetworkConnections]` calls.

 Default is `YES`
 */
@property (nonatomic, readonly) BOOL contributeToExecutingNetworkConnectionsCount;

/**
 Whether the request operation should skip the host sanitization.
 Useful for requests that live in a "walled garden" of always permissible requests.

 Default is `NO`

 __See Also:__ `TNLHostSanitizer`
 */
@property (nonatomic, readonly) BOOL skipHostSanitization;

/**
 The algorithm the request operation should compute a hash of the response body with.
 `executionMode` MUST NOT be `TNLRequestExecutionModeBackground` and
 `responseDataConsumptionMode` MUST NOT be `TNLResponseDataConsumptionModeSaveToDisk`.

 Default is `TNLResponseHashComputeAlgorithmNone` (aka disabled)
 */
@property (nonatomic, readonly) TNLResponseHashComputeAlgorithm responseComputeHashAlgorithm;

/**
 The retry policy provider to use.

 This holds a strong reference, so keep that in mind for implementers of the protocol.
 Best to implement concrete and encapsulated retry policies and not try to adopt the protocol with
 any controller classes such as view controllers.
 @discussion__See Also:__ `TNLRequestRetryPolicyProvider`
 TODO[IOS-55837]: change this to an array of retry policy providers so that more than one can be provided
 */
@property (nonatomic, strong, readonly, nullable) id<TNLRequestRetryPolicyProvider> retryPolicyProvider;

/**
 The custom encoder for the `HTTPBody`.

 Will automatically set the `Content-Encoding` header of the request.
 @note Only works for requests with an `HTTPBody`.
 `HTTPBodyStream` and `HTTPBodyFile` based requests are not supported.
 */
@property (nonatomic, readonly, nullable) id<TNLContentEncoder> contentEncoder;

/**
 The custom decoders for handling the response.

 Based on the `Content-Encoding` of a response, a decoder can be selected.
 `gzip` and `deflate` are automatically supported and should not be provided.
 On iOS 11 / tvOS 11 / watchOS 4 / macOS 10.13, `br` is automatically supported and should not be provided.

 If multiple encoders are provided that have the same content encoding type, the first encoder in
 the array will be used.

 @note Only works with `TNLResponseDataConsumptionModeInMemory` and
 `TNLResponseDataConsumptionModeChunkToDelegateCallback``responseDataConsumptionMode`.
 Does not work with `TNLRequestExecutionModeBackground` `executionMode`
 */
@property (nonatomic, readonly, copy, nullable) NSArray<id<TNLContentDecoder>> *additionalContentDecoders;

/**
 Time permitted between callbacks in the underlying `NSURL` layer.

 This property replaces `[NSURLSessionConfiguration timeoutIntervalForRequest]`

 __Details:__ This timeout has the purpose of capping _idle_ time, time that is spent waiting for
 callbacks from the underlying networking stack.  Whenever a callback is made (such as when a
 response is received, a redirect occurs, data is received, etc), the _idleTimeout_ timer will reset.
 As long as there is activity, the operation won't timeout from the _idleTimeout_.

 @note The minimum interval is `0.1` seconds, anything smaller (including negative) will be treated as _never_.
 */
@property (nonatomic, readonly) NSTimeInterval idleTimeout;

/**
 Time permitted for the underlying _HTTP_ attempt (aka `NSURLSessionTask`).

 This property replaces `[NSURLSessionConfiguration timeoutIntervalForResource]`

 __Details:__ This timeout has the purpose of capping how long an underlying _HTTP_ transaction
 (a.k.a. an attempt) can take before we time out.  If an attempt is executing and not idle, the
 _idleTimeout_ won't be triggered, so this will cap the attempt if it takes too long.

 @note The minimum interval is `0.1` seconds, anything smaller (including negative) will be treated as _never_.
 */
@property (nonatomic, readonly) NSTimeInterval attemptTimeout;

/**
 Time permitted for the entire `TNLRequestOperation` to execute.

 This includes: time in the queue, time per attempt (including retries), time waiting to retry, and
 time spent completing the response

 __Details:__ This timeout has the purpose of capping how long the entire `TNLRequestOperation` has
 to exectue.  This includes time in the queue without starting, redirects, retries, time waiting to
 retry and delegate callbacks.

 @note The minimum interval is `0.1` seconds, anything smaller (including negative) will be treated as _never_.
 */
@property (nonatomic, readonly) NSTimeInterval operationTimeout;

/**
 Time permitted to defer the request when the network is inactive.
 This value is used to optimize the network and device battery performance.

 TODO: Currently unused.  __See also__  `TNLDeferrableIntervalForPriority`.
 */
@property (nonatomic, readonly) NSTimeInterval deferrableInterval;

/**
 default cache policy for requests

 See `[NSURLSessionConfiguration requestCachePolicy]`
 */
@property (nonatomic, readonly) NSURLRequestCachePolicy cachePolicy;

/**
 type of service for requests.

 See `[NSURLSessionConfiguration networkServiceType]`
 */
@property (nonatomic, readonly) NSURLRequestNetworkServiceType networkServiceType;

/**
 how to handle cookies provided by a response

 See `[NSURLSessionConfiguration HTTPCookieAcceptPolicy]`
 Default is `NSHTTPCookieAcceptPolicyNever` in TNL, must explicitely enable cookies
 */
@property (nonatomic, readonly) NSHTTPCookieAcceptPolicy cookieAcceptPolicy;

/**
 whether cookies should be set in the request's headers

 See `[NSURLSessionConfiguration HTTPShouldSetCookies]`
 Default is `NO` in TNL, must explicitely enable cookies
 */
@property (nonatomic, readonly) BOOL shouldSetCookies;

/**
 allow request to route over cellular.

 See `[NSURLSessionConfiguration allowsCellularAccess]`
 */
@property (nonatomic, readonly) BOOL allowsCellularAccess;

/**
 allows background tasks to be scheduled at the discretion of the system for optimal performance.

 See `[NSURLSessionConfiguration discretionary]`
 */
@property (nonatomic, readonly, getter=isDiscretionary) BOOL discretionary;

/**
 The identifier of the shared data container into which files in background sessions/requests should
 be downloaded. App extensions wishing to use background sessions/requests *must* set this property
 to a valid container identifier, or the session will be invalidated upon creation.
 Has no effect below iOS 8.

 See `[NSURLSessionConfiguration sharedContainerIdentifier]`
 */
@property (nonatomic, readonly, copy, nullable) NSString *sharedContainerIdentifier;

/**
 Allows the app to be resumed or launched in the background when tasks/operations in/for background
 sessions/requests complete or when auth is required. This only applies to configurations with
 `exectutionMode` set to `TNLRequestExecutionModeBackground` and the default value is YES.

 Set this to `NO` to avoid having the app launched when the associated request completes.
 See `[NSURLSessionConfiguration sessionSendsLaunchEvents]`.
 */
@property (nonatomic, readonly) BOOL shouldLaunchAppForBackgroundEvents;

/**
 The credential storage object, or `nil` to indicate that no credential storage is to be used.
 Default is `nil`

 See `[NSURLSessionConfiguration URLCredentialStorage]` and
 `[NSURLCredentialStorage tnl_sharedURLCredentialStorage]`
 */
@property (nonatomic, readonly, nullable) NSURLCredentialStorage *URLCredentialStorage;

/**
 The URL resource cache, or `nil` to indicate that no caching is to be performed.
 Default is `nil`.

 See `[NSURLSessionConfiguration URLCache]` and `[NSURLCache tnl_sharedURLCacheProxy]`
 */
@property (nonatomic, readonly, nullable) NSURLCache *URLCache;

/**
 The HTTP cookie storage, or `nil` to indicate that no storage is performed.
 Default is `nil`.

 See `[NSURLSessionConfiguration HTTPCookieStorage]`
 */
@property (nonatomic, readonly, nullable) NSHTTPCookieStorage *cookieStorage;

/**
 The multipath service type.  Default is `NSURLSessionMultipathServiceTypeNone`.
 Requires iOS 11.0.

 See `[NSURLSessionConfiguration multipathServiceType]`
 */
@property (nonatomic, readonly) NSURLSessionMultipathServiceType multipathServiceType API_AVAILABLE(ios(11.0)) API_UNAVAILABLE(macos, watchos, tvos);

/**
 Create a new `TNLRequestConfiguration` instance with default values
 */
+ (instancetype)defaultConfiguration;

/**
 Create a new `TNLRequestConfiguration` instance with timeouts configured appropriately for the provided _anatomy_.

 @param anatomy `TNLRequestAnatomy` the request is presumed to take.
 */
+ (instancetype)configurationWithExpectedAnatomy:(TNLRequestAnatomy)anatomy;

@end

/**
 The mutable version of `TNLRequestConfiguration`

 See `TNLRequestConfiguration`
 */
@interface TNLMutableRequestConfiguration : TNLRequestConfiguration

@property (nonatomic, readwrite) BOOL contributeToExecutingNetworkConnectionsCount;
@property (nonatomic, readwrite) BOOL skipHostSanitization;

@property (nonatomic, readwrite) TNLRequestExecutionMode executionMode;
@property (nonatomic, readwrite) TNLRequestRedirectPolicy redirectPolicy;
@property (nonatomic, readwrite) TNLResponseDataConsumptionMode responseDataConsumptionMode;
@property (nonatomic, readwrite) TNLRequestProtocolOptions protocolOptions;
@property (nonatomic, readwrite) TNLRequestConnectivityOptions connectivityOptions;
@property (nonatomic, readwrite) TNLResponseHashComputeAlgorithm responseComputeHashAlgorithm;

@property (nonatomic, strong, readwrite, nullable) id<TNLRequestRetryPolicyProvider> retryPolicyProvider;
@property (nonatomic, readwrite, nullable) id<TNLContentEncoder> contentEncoder;
@property (nonatomic, readwrite, copy, nullable) NSArray<id<TNLContentDecoder>> *additionalContentDecoders;

@property (nonatomic, readwrite) NSTimeInterval idleTimeout;
@property (nonatomic, readwrite) NSTimeInterval attemptTimeout;
@property (nonatomic, readwrite) NSTimeInterval operationTimeout;
@property (nonatomic, readwrite) NSTimeInterval deferrableInterval;

@property (nonatomic, readwrite) NSURLRequestCachePolicy cachePolicy;
@property (nonatomic, readwrite) NSURLRequestNetworkServiceType networkServiceType;
@property (nonatomic, readwrite) NSHTTPCookieAcceptPolicy cookieAcceptPolicy;
@property (nonatomic, readwrite) BOOL shouldSetCookies;
@property (nonatomic, readwrite) BOOL allowsCellularAccess;
@property (nonatomic, readwrite, getter=isDiscretionary) BOOL discretionary;
@property (nonatomic, readwrite, copy, nullable) NSString *sharedContainerIdentifier;
@property (nonatomic, readwrite) BOOL shouldLaunchAppForBackgroundEvents;
@property (nonatomic, readwrite, nullable) NSURLCredentialStorage *URLCredentialStorage;
@property (nonatomic, readwrite, nullable) NSURLCache *URLCache;
@property (nonatomic, readwrite, nullable) NSHTTPCookieStorage *cookieStorage;
@property (nonatomic, readwrite) NSURLSessionMultipathServiceType multipathServiceType API_AVAILABLE(ios(11.0)) API_UNAVAILABLE(macos, watchos, tvos);

/**
 Populates propertiest that effect prioritization.

 `discretionary` will be set to `YES`.
 `deferrableInterval` will be set to `TNLDeferrableIntervalForPriority(TNLPriorityLow)`
 `networkServiceType` will be set to `NSURLNetworkServiceTypeBackground`
 */
- (void)configureAsLowPriority;

@end

NS_ASSUME_NONNULL_END

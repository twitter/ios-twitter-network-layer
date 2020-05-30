# Twitter Network Layer Change Log

## Info

**Document version:** 2.14.0

**Last updated:** 04/30/2020

**Author:** Nolan O'Brien

## History

### 2.14.0

- Update `TNLCommunicationAgent` to handle reachability behavior changes
  - The `Network.framwork` can yield an "other" interface when VPN is enabled (on Mac binaries)
    - Coerce these into _WiFi_ since we don't have a good way to determine the actual interface used at the moment
  - The `Network.framework` used to yield _WiFi_ for any network connection on a simulator, but now yields _Wired_
    - Rename `TNLNetworkReachabilityReachableViaWiFi` to `TNLNetworkReachabilityReachableViaEthernet` and handle both cases as _Ethernet_

### 2.13.0

- Refactor _Service Unavailable Backoff_ system to be more abstract and support *any* trigger for backoff
  - All `*serviceUnavailableBackoff*` APIs are refactored into `*backoff*` APIs
  - Introduce `[TNLGlobalConfiguration backoffSignaler]`
    - Implement your own `TNLBackoffSignaler` to customize behavior ... or ...
    - Default will use `TNLSimpleBackoffSignaler` which will signal on *HTTP 503*

### 2.12.0

- Abstract out _Service Unavailable Backoff Behavior_ for customization to be applied
  - See `[TNLGlobalConfiguration serviceUnavailableBackoffBehaviorProvider]` for providing a custom backoff behavior
    - Implement your own `TNLServiceUnavailableBackoffBehaviorProvider` to customize behavior
    - Due to _Service Unavailable_ signaling being opaque, only the HTTP Headers and the URL can be provided
  - Default will use `TNLSimpleServiceUnavailableBackoffBehaviorProvider`
    - Exact same behavior as before (introduced in **TNL** prior to v2.0 open sourcing)

### 2.11.0

- Change the `TNLURLSessionAuthChallengeCompletionBlock` arguments
  - Leave the _disposition_ parameter
  - Change the _credentials_ parameter of `NSURLCredentials` to be _credentialsOrCancelContext_ of `id`
    - This will permit `TNLAuthenticationChallengeHandler` instance to be able to cancel the challenge and provide extra context in the resulting error code
    - Twitter will use this to cancel _401_ login auth challenges when we don't want a redundant request to be made (since it just yields the same response)
      - This is to facilitate working around the behavior in `NSURLSession` where an _HTTP 401_ response with `WWW-Authenticate` header will always be transparently be retried (even when unmodified yielding the identical _401_ response).
      - An additionaly problem is that canceling the _401_ response will discard the response's body.  If there is information needed in the response body, it will be lost.
      - Twitter has updated its `WWW-Authenticate` header responses to include additional metadata since the response body cannot be used.
        - See https://tools.ietf.org/html/rfc7235#section-4.1
      - Apple Feedback: `FB7697492`

### 2.10.0

- Add retriable dependencies to `TNLRequestOperation`
  - Whenever a `TNLRetryPolicyProvider` would yield a retry, that retry will be delayed by the longer of 2 things:
    1. The delay provided by the retry policy provider (minimum of 100 milliseconds)
    2. Waiting for all `dependencies` on the `TNLRequestOperation` to complete
    - Normally, all `dependencies` of a retrying `TNLRequestOperation` will be complete before it has started but it is now possible to add dependencies after the request operation has already started to increase the dependencies on a retry starting.

### 2.9.0

- Introduce `tnlcli`, a command-line-interface for __TNL__
  - Like _cURL_ but with __TNL__ features
  - Verbose mode provides all __TNL__ logging to stdout / stderr along with lots of other details

### 2.8.2

- Add _expensive_ and _constrained_ conditions to the reachability flags on iOS 13+
  - `TNLNetworkReachabilityMaskPathConditionExpensive` for when path is expensive
  - `TNLNetworkReachabilityMaskPathConditionConstrained` for when path is constrained

### 2.8.1

- Disable `connectivityOptions` on `TNLRequestConfiguration` for iOS 13.0 (ok on iOS 13.1+)
  - `connectivityOptions` are backed by `NSURLSessionConfiguration` `waitsForConnectivity`
  - `waitsForConnectivity` regressed in iOS 13 betas and is unuseable as a feature on iOS 13.0.
  - iOS 13.1 beta 1 addressed this issue.

### 2.8.0

- Expose `shouldUseExtendedBackgroundIdleMode` in `TNLRequestConfiguration`
  - There's a lot of nuance to this configuration property, so take care when using it 

### 2.7.5

- Change it so that iOS 12 and above use __Network.framework__ for reachability instead of __SystemConfiguration.framework__
  - Reachability in __SystemConfiguration.framework__ has been broken in simulator since iOS 11
  - Reachability in __SystemConfiguration.framework__ will no longer work at all starting in iOS 13
  - Reachability using `nw_path_monitor_t` is the new canonical way to observe reachability changes, so we'll use that
- Change network reachability flags in `TNLCommunicationAgent` from `SCNetworkReachabilityFlags` to `TNLNetworkReachabilityFlags`
  - On iOS 11 and below, the flags are exactly the same as `SCNetworkReachabilityFlags`
  - On iOS 12 and above, the flags now map to the new `TNLNetworkReachabilityMask` flags

### 2.7.0
 
 - Change `TNLRequestConfiguration` to accept a `TNLResponseHashComputeAlgorithm` to specify how to hash
   - MD5 was marked deprecated in iOS 13, so providing a wider range of algorithms without eliminating MD5 support is needed

### 2.6.1

- Fix terrible bug where cancelling all request operations for *any* `TNLRequestOperationQueue` will cancel *all* request operations for *all* queues! 

### 2.6.0

- Move away from mach time for metrics to `NSDate` instances
  - This better mirrors what Apple does
  - Avoids the pitfall of using mach times as more than just measurements of durations and using them as reference timestamps (which is frought)
  - Using `NSDate` now does have the problem of clock changes impacting timings, but this is so infrequent it practically won't ever affect metrics from **TNL**
- Add `sessionId` to `TNLAttemptMetaData`
  - Helps keep track of what `NSURLSession` was used
- Add `taskResumePriority` to `TNLAttemptMetaData`
  - Helps keep track of what QOS was used when `resume` was called for the underlying `NSURLSessionTask`
- Add `taskResumeLatency` to `TNLAttemptMetaData`
  - Helps diagnose if there is some unforseen stall between calling `resume` for the task and the fetching actuallying starting
- Add `taskMetricsAfterCompletionLatency` and `taskWithoutMetricsCompletionLatency` to `TNLAttemptMetaData`
  - Helps track when radar `#27098270` occurs 

### 2.5.0

- Add `[TNLGlobalConfiguration URLSessionPruneOptions]`
  - These options offer ways for __TNL__ to prune inactive internal `NSURLSession` instances more aggressively than the 12 session limit does
  - Options can be a combination of: on memory warning, on app background and/or after every network task
  - Callers can also provide a special option to prune _now_
- Add `[TNLGlobalConfiguration URLSessionInactivityThreshold]`
  - Works with `URLSessionPruneOptions` by limiting what `NSURLSession` intances are _inactive_ by requiring a duration to elapse since the last network task ran
- Add `[TNLGlobalConfiguration pruneURLSessionMatchingRequestConfiguration:operationQueueId:]`
  - Offers a way to explicitely purge a specific underlying `NSURLSession` based on a given `TNLRequestConfiguration` and a `TNLRequestOperationQueue` instance's `identifier`

### 2.4.1

Author: Laurentiu Dascalu
- Expose method on `TNLLogger` to redact desired header fields from being logged
 - Good for redacting things you don't want to log like `Authorization` header field

### 2.4.0
- Add captive portal detection to `TNLCommunicationAgent`
  - detects when a known HTTP (non-HTTPS) endpoint is intercepted via a captive portal
  - this mechanism is a solid tradeoff in coverage vs complexity
    - there are many ways captive portals can manifest beyond what _TNL_ detects
    - a 100% coverage is extremely complicated and 100% accuracy is not feasible
    - supporting the simplest mechanism for detection is sufficient for most detection use cases

### 2.3.0
- Add background upload support using `HTTPBody`
  - TNL will encapsulate the busy-work if there is an upload desire via an `HTTPBody` instead of an `HTTPFilePath`
- Other miscellaneous minor fixes

### 2.2.0
- drop iOS 7 support
  - removes some compatibility check APIs that are no longer necessary too

### 2.1.0

- revise `TNLRetryPolicyProvider` interface to optionally provide a new `TNLRequestConfiguration` when retrying
  - prior interface only permitted updating the _idleTimeout_ which was not sufficient for more use cases
  - example use case: provide a custom content encoder that fails to encode a request, the retry policy and update the configuration to remove the custom content encoder to try again without encoding

### 2.0.2

- add demuxing support for `URLCache`, `URLCredentialStorage`, and `cookieStorage` on `TNLRequestConfiguration`
  - reduces the number of `NSURLSession` instances that need to be spun up

### 2.0.1

- add `waitsForConnectivity` support via `connectivityOptions` for `TNLRequestConfiguration`

### 2.0.0

- Open source *TNL*!!!

### 1.20.0

- Make *TNL* protocols adopt `tnl_` method prefixes

### 1.19.0

- Add support to have `TNLRequestOperation` instances' underlying network operations have dependencies set as the network operation(s) enqueue.
- See `requestOperation:readyToEnqueueUnderlyingNetworkingOperation:`
- Clean up retry policy provider code and event callbacks for disambiguity, and reduced coupling.

### 1.18.0

- Improve auth challenge support
- Create `TNLAuthenticationChallengeHandler`
- Add registration/unregistration on global config for auth challenge handler(s)
- Remove `TNLTLSTrustEvaluator` protocol and property from global config
- Remove auth challenge callback to `TNLRequestAuthorizer` (part of `TNLRequestDelegate`)
- Auth challenges are a shared concept and not associated with any given request specifically
- Handling challenges on a per request basis made for complex code and cascading handling that was unnecessary
- A concrete implementation of a `TNLAuthenticationChallengeHandler` can behave just like a TLS trust evaluator or any number of auth challenge behaviors now.

### 1.17.0

- Elevate `NSNumber` to be a first class object within `TNLParameterCollection`
- Default will encode as a number always.
- URL encoder option to encode Boolean `NSNumber` objects as `true` or `false` instead of `1` and `0`
- Persists the `NSNumber` when creating an encodable dictionary from a `TNLParameterCollection` instead of converting to a string
- This helps with JSON serialization which will want the NSNumber serialized as a number or boolean, instead of a string
- _Twitter Network Layer_ has been stable without revision for 12 months!
- 15 months if you exclude the removal of `CocoaSPDY` which was just removing a plugin feature.

### 1.16.0

- Remove CocoaSPDY support

### 1.15.0

- Add auth hydration step to `TNLRequestAuthorizer`
- this helps decouple things so consumers can hydrate the request in one step and authorize in another
- since TNL has host sanitization, it is often necessary to authorize a request with whatever the sanitized host is.  This decoupling enables that flow very simply.

### 1.14.0

- Add `TNLCommunicationAgent` for communication trait support in __TNL__
- monitors reachability, carrier info and WWAN radio access tech

### 1.13.0

- Add support for custom encoders and decoders for additional `Content-Encoding` types
- Useful for supporting compressed uploads
- Useful for using different compression codecs on responses that could have higher compression ratios than `gzip`

### 1.12.5

- Add `[TNLGlobalConfiguration operationAutomaticDependencyPriorityThreshold]` to support having higher priority requests preventing lower priority requests from running
- The value of this feature is to gate all other network interference when a critical request that much be executed as fast as possible is being run
- This feature takes advantage of the `NSOperation` dependency support

### 1.12.0

- Revise `TNLPseudoURLProtocol` to take a `TNLPseudoURLResponseConfig`
- Offers easier control over the canned responses behavior
- Does change the pattern from the request owning the behavior via headers to the response owning behavior when registered (with a config)
- this is an improvement since it moves the ownership so that the user of `TNLPseudoURLProtocol` doesn't need to control the request being sent

### 1.11.4

- Add `NSURLSessionTaskMetrics` support for iOS 10 and macOS 10.12
- Just tacked onto `TNLAttemptMetrics` for now

### 1.11.3

- Remove long standing workaround in **TNL** to get the `NSURLResponse` of an `NSURLSessionTask` via KVO instead of the delegate callback due to significant problems on iOS 8 & Mac OS X 10.10

### 1.11.2

Author:            Zhen Ma
- Do not call didCompleteAttempt with TNLAttemptCompleteDispositionCompleting when the state is TNLRequestOperationStateWaitingToRetry.

### 1.11.1

Author:            Feng Yun
- Allow multiple global header providers to apply to all requests.

### 1.11.0

- Expose `TNLTiming.h` for timing helper functions
- Fix bug failing to detect Auth Challenge Cancellations
- Add support for global configurable `TNLTLSTrustEvaluator`
- This is placeholder while _CocoaSPDY_ continutes to use a trust evaluator instead of `NSURLAuthenticationChallenge` pattern

### 1.10.1

- Have `[TNLGlobalConfiguration requestOperationCallbackTimeout]` be used to enabled/disable callback clog detection too.  Set it to `0.0` or negative to disable the detection
- Added a bug fix around clog detection when app becomes inactive too

### 1.10.0

- Remove Twitter specific logging framework dependency and expose hooks to provide any desired logger.  *CocoaSPDY* support has its own logger and doesn't share the *TwitterNetworkLayer* logger.

### 1.9.4

- Split callback clogging timeout from idle timeout
- `TNLRequestOperation` instances can clog with the callback timeout, configured on `TNLGlobalConfiguration`
- Callback timeout will _pause_ while an iOS app is in the background

### 1.9.3

- remove `requiresStrongReference` from `TNLRequestDelegate`
- The responsibility of the delegate's lifecycle belongs to the owner of the delegate, not to the delegate itself
- Simplest way to adapt is to make the delegate be the `context` of the operation

### 1.9.2

- Add `TNLAttemptCompleteDisposition` to our attempt completion callbacks in _TNL_.  This will aid in identifying if the attempt will yield additional work (Retry or Redirect) or not (Complete)

### 1.9.1

- iOS 9 has disabled support for subclassing empty `NSURLCache` (they now check the size ivars withouth accessing the property methods).  As such, we need to update our "cache hit detection" code so that it doesn't use a custom `NSURLCache` subclass.
- This means our observing of responses is now more fragile in detecting cache hits.
- `NSCachedURLResponse(TNLCacheAddtions)` and `NSURLResponse(TNLCacheAddtions)` are now exposed so that if cache hit detection is desired w/ an `NSURLCache` that is shared between _TNL_ and some other networking code it can be achieved, though admittedly with burden.
- If networking is isolated to _TNL_, there won't be an issue.

### 1.9.0

- Increase NSURLSession reuse by improving the session identifier used for non-background URL sessions.

### 1.8.5

- Split out NSURLSession work from TNLRequestOperationQueue into a TNLURLSessionManager object.  This will prepare room for betture NSURLSession reuse and modularity in TNL.

### 1.8.4

- Rename TNLConnectionOperation to TNLURLSessionTaskOperation.  This improves naming cohesion for the operation and leaves room for us to add a TNLURLConnectionOperation which would wrap NSURLConnection if we choose to add that support.

### 1.8.3

- Persist NSURLSession instances to maximize reuse

### 1.8.2

Author:            John Zhang
- Added optional idleTimeoutOfRetryForRequestOperation:withResponse: to TNLRequestRetryPolicyProvider protocol
- Handled the return value of idleTimeoutOfRetryForRequestOperation:withResponse: in TNLRequestOperation

### 1.8.1

- Make TNLParameterCollection throw exception on zero length keys
- Treat zero length keys in TNLDecodeDictionary and TNLEncodeDictionary as invalid and discard the key-value-pair when encountered

### 1.8.0

- Make __CocoaSPDY__ optional

### 1.7.6

- Add default TNLURLEncodableObject support to NSNumber

### 1.7.5

- Add valueForResponseHeaderField: to TNLResponseInfo

### 1.7.4

- Collapse TNLHTTPAttempMetaData and TNLSPDYAttemptMetaData into their superclass TNLAttemptMetaData.

### 1.7.3

- Default `TNLRequestConfiguration` to have `nil` for `URLCache`, `URLCredentialStore` and `cookieStore`
- Add `TNLRequestConfiguration` constructor for different request anatomies (request vs response sizes)

### 1.7.2

- Change `requestOperation:didCompleteAttemptWithInfo:metrics:error:` to `requestOperation:didCompleteAttemptWithIntermediateResponse:disposition:`
- This alleviates bugs with dealing with responseClass hydration when observing an attempt

### 1.7.1

- Remove `TNLResponseHydrater`
- Add `Class` argument to `TNLRequestOperation` constructors so that we can provide the _responseClass_

### 1.7.0

- Refactor `TNLResponseHydrater` to provide a `Class` that is ingested by the `TNLRequestOperation` at init time.
- This alleviates a complex surface area that was exposed where the `TNLRequestOperation` is in the `BuildingResponse` state.
- Results in `BuildingResponse` value being removed from `TNLRequestOperationState`.

### 1.6.1

Author:            John Zhang
- Updated TNLHTTPHeaderProvider to pass in a id<TNLRequest> parameter for context

### 1.6.0

- Add nullable/nonnull keywords for Swift interop and compiler optimizations

### 1.5.14

- Permit HTTP Status Codes 202, 203, 207, 208, and 226 to be retriable with a retry policy provider

### 1.5.13

- Add TNLURLEncodableDictionary to TNLURLCoding
- Add encodableDictionaryValueWithOptions: to TNLParameterCollection

### 1.5.12

- Make default behavior for TNLURLEncodeDictionary to throw an exception when an unsupported value is encountered

### 1.5.11

- TNLParameterCollection will now remove the value when `nil` is set as the value

### 1.5.10

Author:            Kevin Goodier
- Added additional CocoaSPDY fields to TNLSPDYAttemptMetadata for stream timings
- Removed support externally for metadata dictionary

### 1.5.9

- Added `TNLHTTPHeaderProvider` support

### 1.5.8

- Provide operation to delegate callbacks that retrieve the background and completion queues

### 1.5.7

Author:            John Zhang
- Added operationId to TNLRequestOperation
- Added attemptId and startTime to TNLAttemptMetrics
- Changed request:didStartAttemptRequest:withType to requestOperation:request:didStartAttemptRequest:metrics in TNLNetworkObserver
- Changed request:didCompleteAttemptWithInfo:metrics:error to requestOperation:didCompleteAttemptWithInfo:metrics:error in TNLNetworkObserver

### 1.5.6

- Update docs
- Change TNLNetwork functions to be class methods on a `TNLNetwork` static class
- Rename `TNLNetworkGlobalExecutingNetworkConnections*` definitions to be `TNLNetworkExecutingNetworkConnections*`

### 1.5.5

- Rename `TNLHTTPRequest` protocol to `TNLRequest`
- This will help disambiguate from the `TNLHTTPRequest` object
- Make `URL` a required method on `TNLRequest`
- Change _NSObject<TNLRequest>_ pattern to _id<TNLRequest>_
- Add more documentation around `TNLRequest`s and hydration

### 1.5.1

- Ensure that the completion callback on the `TNLRequestDelegate` or the completion block is called before the `TNLRequestOperation` finishes
- This will permit `waitUntilFinished` and `waitUntilFinishedWithoutBlockingRunLoop` to return after the callback has completed

### 1.5.0

- Increase compatibility with a more diverse set of requests.
- Permit any request `HTTPMethod` to be an upload, provided it has a body.
- Permit any request `HTTPMethod` to be a download, provided the response data consumption mode is `TNLResponseDataConsumptionModeSaveToDisk`
- There are exceptions that can result in errors based on NSURL framework's restrictions

### 1.4.3

- Add `[TNLAttemptMetrics URLResponse]` and `[TNLAttemptMetrics operationError]`
- This provides a nice trail of breadcrumbs for inspecting the details of how an operation executed

### 1.4.2

- Add support for configuring cookies in `TNLRequestConfiguration`
- Cookies were off by default, now they follow `NSURLSessionConfiguration` defaults

### 1.4.1

- Add `TNLRedirectPolicyUseCallback` to redirect policies
- This exposes additional control to the `TNLRequestRedirecter` protocol (on the `TNLRequestDelegate`) while keeping the simpler configs available

### 1.4.0

- Redefine `TNLNetworkObserver` for much greater utility
- Have the `TNLGlobalConfiguration` support multiple network observers instead of just one

### 1.3.12

- Add `TNLAttemptMetrics` class and `TNLAttemptMetaData` classes for concrete access to metrics and meta-data

### 1.3.11

- Remove `state` property of `TNLRequestOperationQueue`.  It is unused and the backing logic is expensive.  If this functionality is needed in the future we can add it in a more efficient way.

### 1.3.10

- Add support for making in app request operations be background tasks with `TNLRequestExecutionModeInAppBackgroundTask`.  See `[TNLRequestConfiguration executionMode]`.

### 1.3.9

- Add redirect tracking in `TNLResponseMetrics`

### 1.3.8

- Rework `TNLResponseMetrics` to support `[TNLResponseMetrics attemptMetrics]` built of `TNLResponseAttemptMetrics`

### 1.3.7

- Add an optional method to `TNLRequestDelegate` to provide the `completionQueue` which will default to `dispatch_get_main_queue()`.  This will maintain the optimization of defaulting delegate callbacks to a backgroung queue while adding the safety of completing the execution on the main queue to avoid potential gotchas on completion.

### 1.3.6

- Change `[TNLResponse error]` to `[TNLResponse operationError]`

### 1.3.5

- Add `TNLResponseHydrater` protocol for optional response hydration

### 1.3.0

- Greatly improve robustness of `TNLParameterCollection`
- Add encoding configurability with `TNLURLEncodingOptions`
- Add decoding configurability with `TNLURLDecodingOptions`
- Add dynamic support for encoding objects with the `TNLURLEncodableObject` protocol.
- Add `TNLURLEncodeDictionary` function
- Deprecate `TNLURLGenerateParameterString` function
- Add `TNLURLDecodeDictionary` function
- Deprecate `TNLURLGenerateParameterDictionary` function

### 1.2.4

- Add `[TNLRequestEventHandler requestOperation:didReceiveURLResponse:]` delegate callback

### 1.2.3

- Add proxy objects for `[NSURLCache tnl_shareURLCache]` and `[NSURLCredentialStorage tnl_shareCredentialStorage]`
- Make proxy objects defaults of `TNLRequestConfiguration`

### 1.2.2

- Add convenience "Retry-After" header support to `TNLResponseInfo`

### 1.2.1

- Change default `TNLRequestRedirectPolicy` to be `TNLRequestRedirectPolicyDoRedirect`

### 1.2.0

- Completely encapsulate __CocoaSPDY__
- `TNLGlobalConfiguration(CocoaSPDYAdditions)`
- `[TNLRequestConfiguration protocolOptions]`
- `TNLCocoaSPDYConfiguration`
- `[TNLResponseMetrics cocoaSPDYMetaData]`
- `TNLCocoaSPDY.h`

### 1.1.1

- Remove `NSCopying` requirement from `TNLHTTPRequest` protocol
- Add `NSCopying` support to `TNLParameterCollection`

### 1.1.0

- Rework delegate pattern for `TNLRequestOperation`.  #simplify

### 1.0.2

- Add support for URL host sanitization

### 1.0.1

- Prevent `[TNLRequestOperationQueue defaultOperationQueue]` from being suspended

### 1.0.0 (11/17/2014)

- Initial release

### beta (06/09/2014)

- Inaugural beta

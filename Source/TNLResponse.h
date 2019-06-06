//
//  TNLResponse.h
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <TwitterNetworkLayer/TNLHTTP.h>
#import <TwitterNetworkLayer/TNLRequest.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TNLTemporaryFile;
@class TNLAttemptMetrics;
@class TNLResponseMetrics;
@class TNLResponseInfo;

/**
 The enum representing the source that the response came from
 */
typedef NS_ENUM(NSInteger, TNLResponseSource) {
    /** Unknown */
    TNLResponseSourceUnknown = 0,
    /** The response was retrieved from a local cache */
    TNLResponseSourceLocalCache,
    /** The response was retrieved via a network request */
    TNLResponseSourceNetworkRequest
};

/**
 The response object that results from a network request completing.

 The `TNLResponse` object encapsulates all the response information into a single object.

 __TNL__ offers powerful response support by permitting callers to provide their own `TNLResponse`
 subclass `Class` to `TNLRequestOperation` creation.  Subclassing is as simple as implementing the
 `prepare` method and, after calling super, parsing whatever response details are necessary to
 populate the subclasses properties.

 __See also__: `TNLResponseInfo` and `TNLResponseMetrics`

 @warning `[TNLResponse supportsSecureCoding]` returns `YES` even if `originalRequest` does not
 support secure coding and will encode the `originalRequest` as a `TNLResponseEncodedRequest`.
 */
@interface TNLResponse : NSObject <NSSecureCoding>
{
@protected
    NSError *_operationError;
    id<TNLRequest> _originalRequest;
    TNLResponseInfo *_info;
    TNLResponseMetrics *_metrics;
}

/**
 If an error was encountered during the `TNLRequestOperation`, this property will be populated.

 See `TNLErrorCode` for __TNL__ specific errors.
 @note An error is ___not___ set when the HTTP Status code represents a client _(4xx)_ or
 server _(5xx)_ error.  Receiving one of those status codes indicates a successful network request
 with a valid response.  Treating client and server error status codes as errors is up to the caller
 and out of scope for __TNL__.  Consider subclassing `TNLResponse` to expose an `HTTPError` property.
 */
@property (nonatomic, readonly, nullable) NSError *operationError;

/**
 The originating request

 See `[TNLRequestOperation originalRequest]`.
 */
@property (nonatomic, readonly, copy, nullable) id<TNLRequest> originalRequest;

/**
 The compilation of response information.

 See `TNLResponseInfo`
 */
@property (nonatomic, readonly) TNLResponseInfo *info;

/**
 The compilation of metrics.

 See `TNLResponseMetrics`
 */
@property (nonatomic, readonly) TNLResponseMetrics *metrics;

/**
 Constructor - call this to construct a new `TNLResponse` (or construct a subclass)
 */
+ (instancetype)responseWithRequest:(nullable id<TNLRequest>)originalRequest
                     operationError:(nullable NSError *)operationError
                               info:(TNLResponseInfo *)info
                            metrics:(TNLResponseMetrics *)metrics
NS_SWIFT_NAME(response(request:operationError:info:metrics:));

/** Unavailable */
- (instancetype)init NS_UNAVAILABLE;
/** Unavailable */
+ (instancetype)new NS_UNAVAILABLE;

/**
 Constructor to create a new response from an existing response.

 Useful when creating a subclassed response for extending the `TNLResponse`.
 @param response the response to create a new response from
 @return the new response

 __Do NOT override this method.__
 */
+ (instancetype)responseWithResponse:(TNLResponse *)response;

@end

@interface TNLResponse (Protected)

/**
 Method called to prepare the `TNLResponse` (or subclass) after it has initialized.
 Subclasses SHOULD override this method to customize their construction.
 CAN set `[TNLAttemptMetrics APIErrors]` and/or `[TNLAttemptMetrics responseBodyParseError]`
 for the latest attempt in `self.metrics.attemptMetrics`.
 __Do NOT call this method.__

 Be sure to set `CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS` to `YES` in your build settings.
 */
- (void)prepare NS_REQUIRES_SUPER;

/**
 __Do NOT override this method.__
 __Do NOT call this method.__
 _Don't even look at it._
 Method declaration is present for compiler support to avoid overriding it.

 Be sure to set `CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS` to `YES` in your build settings.
 */
- (instancetype)initWithRequest:(nullable id<TNLRequest>)originalRequest
                 operationError:(nullable NSError *)operationError
                           info:(TNLResponseInfo *)info
                        metrics:(TNLResponseMetrics *)metrics __attribute__((deprecated("use +responseWithRequest:operationError:info:metrics: instead")));

@end

/**
 Object encapsulating the response information

 See `TNLResponse`
 */
@interface TNLResponseInfo : NSObject <NSSecureCoding>

/** The final `NSURLRequest` that was used in the network connection */
@property (nonatomic, readonly, nullable) NSURLRequest *finalURLRequest;

/** The final `NSHTTPURLResponse` object that was received by the network connection */
@property (nonatomic, readonly, nullable) NSHTTPURLResponse *URLResponse;

/**
 The response body if _responseDataConsumptionMode_ was set to `TNLResponseDataConsumptionModeStoreInMemory`.

 See `TNLRequestConfiguration`
 */
@property (nonatomic, readonly, nullable) NSData *data;

/**
 The temporary file holding the response body if _responseDataConsumptionMode_ was set to
 `TNLResponseDataConsumptionModeSaveToDisk`.

 See `TNLRequestConfiguration` and `TNLTemporaryFile`

 The temporary file will only survive as long as the response object, then will be deleted.
 Use `[TNLTemporaryFile moveToPath:error:]` on this property to persist the downloaded file.

 @note the temporary file will not be persisted when using `NSCoding` archival.
 The unarchived `TNLResponseInfo` will have a `TNLTemporaryFile` that will always fail
 `[TNLTemporaryFile moveToPath:error:]` since the unarchived response will not own the temporary file.
 */
@property (nonatomic, readonly, nullable) id<TNLTemporaryFile> temporarySavedFile;

/**
 The source of the response

 See `TNLResponseSource`
 */
@property (nonatomic, readonly) TNLResponseSource source;

/** Designated initializer */
- (instancetype)initWithFinalURLRequest:(nullable NSURLRequest *)finalURLRequest
                            URLResponse:(nullable NSHTTPURLResponse *)URLResponse
                                 source:(TNLResponseSource)source
                                   data:(nullable NSData *)data
                     temporarySavedFile:(nullable id<TNLTemporaryFile>)temporarySavedFile NS_DESIGNATED_INITIALIZER;

/** Unavailable */
- (instancetype)init NS_UNAVAILABLE;
/** Unavailable */
+ (instancetype)new NS_UNAVAILABLE;

@end

/**
 __TNLResponseInfo (Convenience)__

 Convenience methods for `TNLResponseInfo`
 */
@interface TNLResponseInfo (Convenience)

/** Same as _URLResponse.statusCode_ */
@property (nonatomic, readonly) TNLHTTPStatusCode statusCode;

/** Same as _URLResponse.URL ?: _finalURLRequest.URL_ */
@property (nonatomic, readonly, nullable) NSURL *finalURL;

/** Same as _URLResponse.allHTTPHeaderFields_ */
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields;

/** Return the value of the response header field, using headerField as a case-insensitive key. */
- (nullable NSString *)valueForResponseHeaderField:(NSString *)headerField;

/** Returns a copy of the _allHTTPHeaderFields_ with only lowercase keys */
- (nullable NSDictionary<NSString *, NSString *> *)allHTTPHeaderFieldsWithLowerCaseKeys;

@end

/**
 __TNLResponseInfo (RetryAfter)__

 Convenience methods gathering Retry-After information from `TNLResponseInfo`
 */
@interface TNLResponseInfo (RetryAfter)

/** Convenience method for determining if there is a Retry-After header */
@property (nonatomic, readonly) BOOL hasRetryAfterHeader;

/** Convenience method for retrieving the Retry-After raw value */
@property (nonatomic, readonly, nullable) NSString *retryAfterRawValue;

/**
 Convenience method for retrieving the Retry-After date value as an `NSDate`.
 Returns `nil` if value could not be parsed
 */
@property (nonatomic, readonly, nullable) NSDate *retryAfterDate;

/**
 Convenience method for retrieving the Retry-After delay value in seconds from the now.
 Returns `NSTimeIntervalSince1970` if value could not be parsed.
 Value can be negative if it occurs in the past.
 */
- (NSTimeInterval)retryAfterDelayFromNow;

@end

/**
 Converted request for Secure Coding
 */
@interface TNLResponseEncodedRequest : NSObject <TNLRequest, NSSecureCoding>

/** The name of the source `TNLRequest` class that was encoded */
@property (nonatomic, readonly, copy, nullable) NSString *encodedSourceRequestClassName;
/** If the encoded source request has a body */
@property (nonatomic, readonly) BOOL encodedSourceRequestHadBody;

/** Unavailable */
- (instancetype)init NS_UNAVAILABLE;
/** Unavailable */
+ (instancetype)new NS_UNAVAILABLE;

@end

/**
 Object encapsulating the metrics related the to request operation

 The `TNLResponseMetrics` object encapsulates all the execution metrics and meta-data of finished
 (completed, cancelled or failed) `TNLRequestOperation`.  The object itself offers macro insight such
 as the number of _HTTP_ attempts that occurred in the operation (_attemptCount_) and the total
 duration of the operation (_totalDuration_).

 At a more micro level, the `TNLAttemptMetrics` can be accessed via the _attemptMetrics_ property.
 As you are inspecting attempt metrics, the meta-data of the attempt may also be of use and can be
 accessed from `[TNLAttemptMetrics metaData]` as `TNLAttemptMetaData`.

 See also `TNLResponse`
 */
@interface TNLResponseMetrics : NSObject <NSSecureCoding>

/** When the `TNLRequestOperation` was enqueued to its `TNLRequestOperationQueue` as `NSDate` */
@property (nonatomic, readonly) NSDate *enqueueDate;
/** When the `TNLRequestOperation` was enqueued to its `TNLRequestOperationQueue` */
@property (nonatomic, readonly) uint64_t enqueueMachTime __attribute__((deprecated("use enqueueDate instead")));
/** When the `TNLRequestOperation` completed as `NSDate` */
@property (nonatomic, readonly, nullable) NSDate *completeDate;
/** When the `TNLRequestOperation` completed */
@property (nonatomic, readonly) uint64_t completeMachTime __attribute__((deprecated("use completeDate instead")));

/** The number of attempts that occurred (initial attempt + retries + redirects) */
@property (nonatomic, readonly) NSUInteger attemptCount;
/** The number of retries that occurred */
@property (nonatomic, readonly) NSUInteger retryCount;
/** The number of redirects that occurred */
@property (nonatomic, readonly) NSUInteger redirectCount;

/** The underlying attempt metrics as `TNLAttemptMetrics` objects */
@property (nonatomic, readonly, nullable) NSArray<TNLAttemptMetrics *> *attemptMetrics;

/**
 Helper init for custom `TNLResponseMetrics`
 */
- (instancetype)initWithEnqueueDate:(NSDate *)enqueueDate
                        enqueueTime:(uint64_t)enqueueTime
                       completeDate:(nullable NSDate *)completeDate
                       completeTime:(uint64_t)completeTime
                     attemptMetrics:(nullable NSArray<TNLAttemptMetrics *> *)attemptMetrics;

@end

/**
 Convenience methods on `TNLResponseMetrics`
 */
@interface TNLResponseMetrics (Convenience)

/** When the first attempt started (after the time spent waiting in the queue) as `NSDate` */
@property (nonatomic, readonly, nullable) NSDate *firstAttemptStartDate;
/** When the first attempt started (after the time spent waiting in the queue) */
@property (nonatomic, readonly) uint64_t firstAttemptStartMachTime __attribute__((deprecated("use firstAttemptStartDate instead")));
/** When the current attempt started as `NSDate` */
@property (nonatomic, readonly, nullable) NSDate *currentAttemptStartDate;
/** When the current attempt started */
@property (nonatomic, readonly) uint64_t currentAttemptStartMachTime __attribute__((deprecated("use currentAttemptStartDate instead")));
/** When the current attempt ended as `NSDate` */
@property (nonatomic, readonly, nullable) NSDate *currentAttemptEndDate;
/** When the current attempt ended */
@property (nonatomic, readonly) uint64_t currentAttemptEndMachTime __attribute__((deprecated("use currentAttemptEndDate instead")));

/** calculate the total duration of the operation */
- (NSTimeInterval)totalDuration;
/** calculate the duration that operation was in the queue but not yet started */
- (NSTimeInterval)queuedDuration;
/**
 calculate the duration the operation took to execute upon all attempts (including retries).
 This excludes queued time but does include time spent waiting to retry.
 */
- (NSTimeInterval)allAttemptsDuration;
/** calculate the duration that the current attempt took */
- (NSTimeInterval)currentAttemptDuration;

@end

/**
 Convenience methods that are useful for testing `TNLResponseMetrics`.
 Should not be used for production code.
 */
@interface TNLResponseMetrics (UnitTesting)

/**
 Construct a `TNLResponseMetrics` instance from the provided arguments.
 This will be a fake set of metrics since this will not hydrate the metrics with the natural
 mechanism encapsulated by `TNLRequestOperation`.

 @param duration    The `totalDuration` of the metrics.  `firstAttemptStartMachTime` will be `0`.
 @param URLRequest  The `NSURLRequest` for the encapsulated attempt
 @param URLResponse The `NSHTTPURLResponse` for the encapsulated attempt
 @param error       The `NSError` for the encapsulated attempt

 @return a fake `TNLResponseMetrics` object with a single attempt being encapsulated.
 */
+ (instancetype)fakeMetricsForDuration:(NSTimeInterval)duration
                            URLRequest:(NSURLRequest *)request
                           URLResponse:(nullable NSHTTPURLResponse *)URLResponse
                        operationError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END

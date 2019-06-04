//
//  TNLAttemptMetrics.h
//  TwitterNetworkLayer
//
//  Created on 1/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLCommunicationAgent.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLAttemptMetaData;
@class NSURLSessionTaskTransactionMetrics;

/**
 The enum representing the type of an `TNLRequestOperation`'s underyling attempt.
 */
typedef NS_ENUM(NSInteger, TNLAttemptType) {
    /** Initial Attempt */
    TNLAttemptTypeInitial = 0,
    /** Redirect Attempt */
    TNLAttemptTypeRedirect,
    /** Retry Attempt */
    TNLAttemptTypeRetry,

    // NOTE: be sure to update TNLAttemptTypeCount if you add values to this enum
};

static const NSInteger TNLAttemptTypeCount = 3;
FOUNDATION_EXTERN NSString * __nullable TNLAttemptTypeToString(TNLAttemptType type);

/**
 Attempt complete disposition: values representing the disposition of an attempt completing.
 Given that an attempt completing can yield additional work (retry or redirect), this can offer
 value to observers/delegates.

 See `TNLRequestEventHandler`

 @note despite `Redirecting` and `Retrying` values indicating that another attempt will be made,
 it does not guarantee that the subsequent attempt will happen since a timeout or cancellation could
 prevent that attempt from starting.
 */
typedef NS_ENUM(NSInteger, TNLAttemptCompleteDisposition) {
    /** The attempt is a completion attempt.  No more future attempts will be performed. */
    TNLAttemptCompleteDispositionCompleting = TNLAttemptTypeInitial,
    /** The attempt yielded a redirect.  There will be a follow up attempt with this redirect. */
    TNLAttemptCompleteDispositionRedirecting = TNLAttemptTypeRedirect,
    /** The attempt yielded a retry.  There will be a follow up attempt to retry. */
    TNLAttemptCompleteDispositionRetrying = TNLAttemptTypeRetry,
};

static const NSInteger TNLAttemptCompleteDispositionCount = 3;

/**
 Base class for encapsulating the metrics related to the underlying attempt of a `TNLRequestOperation`.
 */
@interface TNLAttemptMetrics : NSObject <NSSecureCoding, NSCopying>

/** The randomly generated id of the attempt */
@property (nonatomic, readonly) int64_t attemptId;
/** The type of the attempt */
@property (nonatomic, readonly) TNLAttemptType attemptType;

/** attempt start date */
@property (nonatomic, readonly) NSDate *startDate;
/** attempt start machine time */
@property (nonatomic, readonly) uint64_t startMachTime;
/** attempt end date */
@property (nonatomic, readonly, nullable) NSDate *endDate;
/** attempt end machine time */
@property (nonatomic, readonly) uint64_t endMachTime;

/** The associated `TNLAttemptMetaData` (if any) */
@property (nonatomic, readonly, nullable) TNLAttemptMetaData *metaData;

#if !TARGET_OS_WATCH
/** attempt reachability status */
@property (nonatomic, readonly) TNLNetworkReachabilityStatus reachabilityStatus;
/** attempt reachability flags */
@property (nonatomic, readonly) SCNetworkReachabilityFlags reachabilityFlags;
/** attempt radio access technology */
@property (nonatomic, copy, readonly, nullable) NSString *WWANRadioAccessTechnology;
/** attempt carrier info. Note: `nil` for macOS since there is no cellular carrier information */
@property (nonatomic, readonly, nullable) id<TNLCarrierInfo> carrierInfo;
/** attempt captive portal status */
@property (nonatomic, readonly) TNLCaptivePortalStatus captivePortalStatus;
#endif // !TARGET_OS_WATCH

/** The related request for this attempt */
@property (nonatomic, readonly, copy) NSURLRequest *URLRequest;
/** The related response (if any) for this attempt */
@property (nonatomic, readonly, nullable) NSHTTPURLResponse *URLResponse;
/** The related operation error (if any) for this attempt */
@property (nonatomic, readonly, nullable) NSError *operationError;
/** The related `NSURLSessionTaskTransactionMetrics` (if any) for this attempt */
@property (nonatomic, readonly, nullable) NSURLSessionTaskTransactionMetrics *taskTransactionMetrics NS_AVAILABLE(10_12, 10_0);

/**
 The optional API errors associated with this attempt.
 Set by `TNLResponse` subclass implemenation.
 See `[TNLResponse prepare]`.
 */
@property (nonatomic, readonly, copy, nullable) NSArray<NSError *> *APIErrors;

/**
 The optional parse error associated with this attempt's response body being parsed.
 Set by `TNLResponse` subclass implementation.
 See `[TNLResponse prepare]`.
 */
@property (nonatomic, readonly, nullable) NSError *responseBodyParseError;

/** Designated Initializer */
- (instancetype)initWithAttemptId:(int64_t)attemptId
                             type:(TNLAttemptType)type
                        startDate:(NSDate *)startDate
                    startMachTime:(uint64_t)startMachTime
                          endDate:(nullable NSDate *)endDate
                      endMachTime:(uint64_t)endMachTime
                         metaData:(nullable TNLAttemptMetaData *)metaData
                       URLRequest:(NSURLRequest *)request
                      URLResponse:(nullable NSHTTPURLResponse *)response
                   operationError:(nullable NSError *)error NS_DESIGNATED_INITIALIZER;

/** Initializer */
- (instancetype)initWithType:(TNLAttemptType)type
                   startDate:(NSDate *)startDate
               startMachTime:(uint64_t)startMachTime
                     endDate:(nullable NSDate *)endDate
                 endMachTime:(uint64_t)endMachTime
                    metaData:(nullable TNLAttemptMetaData *)metaData
                  URLRequest:(NSURLRequest *)request
                 URLResponse:(nullable NSHTTPURLResponse *)response
              operationError:(nullable NSError *)error;

/** Unavailable */
- (instancetype)init NS_UNAVAILABLE;
/** Unavailable */
+ (instancetype)new NS_UNAVAILABLE;

/** calculate the duration of the attempt */
- (NSTimeInterval)duration;

@end

/**
 Methods exposed that `[TNLResponse prepare]` can use
 */
@interface TNLAttemptMetrics (TNLResponse)

/**
 Can set `APIErrors` during `[TNLResponse prepare]` callback.
 Otherwise, setter is noop.
 */
@property (nonatomic, copy, nullable) NSArray<NSError *> *APIErrors;
/**
 Can set `responseBodyParseError` during `[TNLResponse prepare]` callback.
 Otherwise, setter is noop.
 */
@property (nonatomic, nullable) NSError *responseBodyParseError;

@end

NS_ASSUME_NONNULL_END

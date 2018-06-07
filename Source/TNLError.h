//
//  TNLError.h
//  TwitterNetworkLayer
//
//  Created on 7/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const TNLErrorDomain;

FOUNDATION_EXTERN NSString * const TNLErrorTimeoutTagsKey;
FOUNDATION_EXTERN NSString * const TNLErrorCancelSourceKey;
FOUNDATION_EXTERN NSString * const TNLErrorCancelSourceDescriptionKey;
FOUNDATION_EXTERN NSString * const TNLErrorCancelSourceLocalizedDescriptionKey;
FOUNDATION_EXTERN NSString * const TNLErrorCodeStringKey;
FOUNDATION_EXTERN NSString * const TNLErrorHostKey;
FOUNDATION_EXTERN NSString * const TNLErrorRequestKey;
FOUNDATION_EXTERN NSString * const TNLErrorProtectionSpaceHostKey;
FOUNDATION_EXTERN NSString * const TNLErrorCertificateChainDescriptionsKey;
FOUNDATION_EXTERN NSString * const TNLErrorAuthenticationChallengeMethodKey;

#define TNLErrorCodePageSize        (100)

#define TNLErrorCodePageRequest             (1 * TNLErrorCodePageSize)
#define TNLErrorCodePageRequestOperation    (2 * TNLErrorCodePageSize)
#define TNLErrorCodePageGlobal              (3 * TNLErrorCodePageSize)
#define TNLErrorCodePageOther               (99 * TNLErrorCodePageSize)

#define TNLErrorCodeIsRequestError(code)            (((code) / TNLErrorCodePageSize) == (TNLErrorCodePageRequest / TNLErrorCodePageSize))
#define TNLErrorCodeIsRequestOperationError(code)   (((code) / TNLErrorCodePageSize) == (TNLErrorCodePageRequestOperation / TNLErrorCodePageSize))
#define TNLErrorCodeIsGlobalError(code)             (((code) / TNLErrorCodePageSize) == (TNLErrorCodePageGlobal / TNLErrorCodePageSize))

/**
 Twitter Network Layer error code

 ## TNLErrorCodeToString

     FOUNDATION_EXTERN NSString *TNLErrorCodeToString(TNLErrorCode code);

 Convert a `TNLErrorCode` to an `NSString` representation

 ## [NSError domain] for TNL

     FOUNDATION_EXTERN NSString * const TNLErrorDomain

 ## [NSError userInfo] keys in TNL

     // The tags that have been set for active callbacks that were occurring when a timeout occurred
     FOUNDATION_EXTERN NSString * const TNLErrorTimeoutTagsKey
     // The source object that caused the `TNLRequestOperation` to cancel
     FOUNDATION_EXTERN NSString * const TNLErrorCancelSourceKey
     // The description of the source object that caused the `TNLRequestOperation` to cancel
     FOUNDATION_EXTERN NSString * const TNLErrorCancelSourceDescriptionKey
     // The localized and user presentable description of the source object that caused the `TNLRequestOperation` to cancel
     FOUNDATION_EXTERN NSString * const TNLErrorCancelSourceLocalizedDescriptionKey
     // A string representation of the `TNLErrorCode`
     FOUNDATION_EXTERN NSString * const TNLErrorCodeStringKey
     // The URL's host
     FOUNDATION_EXTERN NSString * const TNLErrorHostKey

 ## Helper Macros/Functions

     TNLErrorCodeIsRequestError(code)           // the code is a TNLHTTPRequest error
     TNLErrorCodeIsRequestOperationError(code)  // the code is a TNLRequestOperation error
     TNLErrorCodeIsGlobalError(code)            // the code is a global error
     TNLErrorCodeIsTerminal(code)               // the code is terminal (cannot be retried)

 ## TNLErrorCode

 */
typedef NS_ENUM(NSInteger, TNLErrorCode) {
    /** Unknown error */
    TNLErrorCodeUnknown = 0,

    // Request Error Codes

    /** Generic `TNLRequest` error */
    TNLErrorCodeRequestGenericError = TNLErrorCodePageRequest,

    /** Invalid `TNLRequest` */
    TNLErrorCodeRequestInvalid,

    /** Invalid URL on a `TNLRequest` */
    TNLErrorCodeRequestInvalidURL,

    /** Invalid HTTP Method on a `TNLRequest` */
    TNLErrorCodeRequestInvalidHTTPMethod,

    /**
     When the execution mode is `TNLResponseDataConsumptionModeSaveToDisk`, the HTTP Body must not
     be set.  This is because simultaneous uploading a body and downloading a file is not supported.
     */
    TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload,

    /**
     Background requests must either upload data (via file) or download data (to a file).
     For upload, set an HTTP Body (with `HTTPBodyFilePath`).
     For download, set the execution mode to `TNLResponseDataConsumptionModeSaveToDisk`.
     NOTE: background uploading a body without a file (`HTTPBody` or `HTTPBodyStream`) is also
     invalid and will yield this error.
     */
    TNLErrorCodeRequestInvalidBackgroundRequest,




    // Request Operation Error Codes

    /** Generic `TNLRequestOperation` error */
    TNLErrorCodeRequestOperationGenericError = TNLErrorCodePageRequestOperation,

    /**
     The request operation was cancelled.
     The `NSError` object's `userInfo` will contain a `TNLErrorCancelSourceKey` KVP, a
     `TNLErrorCancelSourceDescriptionKey` KVP, (optionally) a
     `TNLErrorCancelSourceLocalizedDescriptionKey` and (optionally) an `NSUnderlyingErrorKey` KVP.
     See `[TNLRequestOperation cancelWithSource:underlyingError:]` and
     `[TNLRequestOperationQueue cancelAllWithSource:underlyingError:]`.
     */
    TNLErrorCodeRequestOperationCancelled,

    /** The request operation timed out.  See `[TNLRequestConfiguration operationTimeout]`. */
    TNLErrorCodeRequestOperationOperationTimedOut,

    /** The request attempt timed out.  See `[TNLRequestConfiguration attemptTimeout]`. */
    TNLErrorCodeRequestOperationAttemptTimedOut,

    /** The request timed out due to idleness.  See `[TNLRequestConfiguration idleTimeout]`. */
    TNLErrorCodeRequestOperationIdleTimedOut,

    /** The request times out due to a delegate/retry-policy callback taking too long (10 seconds). */
    TNLErrorCodeRequestOperationCallbackTimedOut,

    /** The request operation was not provided an object that conforms to the `TNLRequest` protocol. */
    TNLErrorCodeRequestOperationRequestNotProvided,

    /** The `TNLRequest` could not be hydrated. The `NSUnderlyingError` key will be set. */
    TNLErrorCodeRequestOperationFailedToHydrateRequest,

    /**
     The hydrated `TNLRequest` is not valid.
     The `NSUnderlyingError` will be set - usually a `TNLErrorCodeRequestBLAH` error.
     */
    TNLErrorCodeRequestOperationInvalidHydratedRequest,

    /** There was an I/O error */
    TNLErrorCodeRequestOperationFileIOError,

    /** There was an issue appending received data to memory */
    TNLErrorCodeRequestOperationAppendResponseDataError,

    /**
     The underlying NSURLSession became invalid.
     If the invalidation is systemic, the `NSUnderlyingError` will be set.
     */
    TNLErrorCodeRequestOperationURLSessionInvalidated,

    /** Authentication challenge was cancelled */
    TNLErrorCodeRequestOperationAuthenticationChallengeCancelled,

    /**
     The request's `"Content-Encoding"` HTTP field was specified and it did not match the specified
     `TNLContentEncoder` on the `TNLRequestConfiguration`
     */
    TNLErrorCodeRequestOperationRequestContentEncodingTypeMissMatch,

    /**
     The request's body failed to be encoded with the specified `TNLContentEncoder` on the
     `TNLRequestConfiguration`
     */
    TNLErrorCodeRequestOperationRequestContentEncodingFailed,

    /**
     The response's body failed to be decoded with the matching `TNLContentDecoder` specified by
     `TNLRequestConfiguration`
     */
    TNLErrorCodeRequestOperationRequestContentDecodingFailed,

    /** The operation could not authorize its request. */
    TNLErrorCodeRequestOperationFailedToAuthorizeRequest,




    // Global Error Codes

    /** Generic global error */
    TNLErrorCodeGlobalGenericError = TNLErrorCodePageGlobal,

    /**
     The URL host was blocked by the `TNLGlobalConfiguration`'s `TNLHostSanitizer`.
     `TNLErrorHostKey` will be set.
     */
    TNLErrorCodeGlobalHostWasBlocked,




    // Other Error Codes

    /** Generic other error */
    TNLErrorCodeOtherGenericError = TNLErrorCodePageOther,

    /** The URL host was empty */
    TNLErrorCodeOtherHostCannotBeEmpty,
};

//! Convert `TNLErrorCode` to an `NSString`
FOUNDATION_EXTERN NSString * __nullable TNLErrorCodeToString(TNLErrorCode code);
//! Return `YES` if the `TNLErrorCode` is a terminal code and cannot be retried
FOUNDATION_EXTERN BOOL TNLErrorCodeIsTerminal(TNLErrorCode code);
//! Return `YES` if the `NSError` is a network security error, possibly due to Apple's _App Transport Security_
FOUNDATION_EXTERN BOOL TNLErrorIsNetworkSecurityError(NSError * __nullable error);

#if APPLEDOC
/**
 A series APIs for dealing with __TNL__ errors. See `TNLErrorCode`.
 */
@interface TNLError
@end
#endif

#pragma mark - NSError helpers for TNL

//! Standard error codes for `NSURLErrorDomain` errors that can be retried
FOUNDATION_EXTERN NSArray<NSNumber *> *TNLStandardRetriableURLErrorCodes(void);
//! Standard error codes for `NSPOSIXErrorDomain` errors that can be retried
FOUNDATION_EXTERN NSArray<NSNumber *> *TNLStandardRetriablePOSIXErrorCodes(void);

NS_ASSUME_NONNULL_END

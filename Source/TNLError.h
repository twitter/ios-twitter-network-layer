//
//  TNLError.h
//  TwitterNetworkLayer
//
//  Created on 7/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TNLRequestOperationCancelSource;

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
    TNLErrorCodeRequestGenericError = TNLErrorCodePageRequest, // 100

    /** Invalid `TNLRequest` */
    TNLErrorCodeRequestInvalid = 101,

    /** Invalid URL on a `TNLRequest` */
    TNLErrorCodeRequestInvalidURL = 102,

    /** Invalid HTTP Method on a `TNLRequest` */
    TNLErrorCodeRequestInvalidHTTPMethod = 103,

    /**
     When the execution mode is `TNLResponseDataConsumptionModeSaveToDisk`, the HTTP Body must not
     be set.  This is because simultaneous uploading a body and downloading a file is not supported.
     */
    TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload = 104,

    /**
     Background requests must either upload data (via file) or download data (to a file).
     For upload, set an HTTP Body (with `HTTPBodyFilePath`).
     For download, set the execution mode to `TNLResponseDataConsumptionModeSaveToDisk`.
     NOTE: background uploading a body without a file (`HTTPBody` or `HTTPBodyStream`) is also
     invalid and will yield this error.  The _NSURLSession_ docs are incorrect, which falsely state that any `NSURLSessionUploadTask` will work on a background session.
     */
    TNLErrorCodeRequestInvalidBackgroundRequest = 105,




    // Request Operation Error Codes

    /** Generic `TNLRequestOperation` error */
    TNLErrorCodeRequestOperationGenericError = TNLErrorCodePageRequestOperation, // 200

    /**
     The request operation was cancelled.
     The `NSError` object's `userInfo` will contain a `TNLErrorCancelSourceKey` KVP, a
     `TNLErrorCancelSourceDescriptionKey` KVP, (optionally) a
     `TNLErrorCancelSourceLocalizedDescriptionKey` and (optionally) an `NSUnderlyingErrorKey` KVP.
     See `[TNLRequestOperation cancelWithSource:underlyingError:]` and
     `[TNLRequestOperationQueue cancelAllWithSource:underlyingError:]`.
     */
    TNLErrorCodeRequestOperationCancelled = 201,

    /** The request operation timed out.  See `[TNLRequestConfiguration operationTimeout]`. */
    TNLErrorCodeRequestOperationOperationTimedOut = 202,

    /** The request attempt timed out.  See `[TNLRequestConfiguration attemptTimeout]`. */
    TNLErrorCodeRequestOperationAttemptTimedOut = 203,

    /** The request timed out due to idleness.  See `[TNLRequestConfiguration idleTimeout]`. */
    TNLErrorCodeRequestOperationIdleTimedOut = 204,

    /** The request times out due to a delegate/retry-policy callback taking too long (10 seconds). */
    TNLErrorCodeRequestOperationCallbackTimedOut = 205,

    /** The request operation was not provided an object that conforms to the `TNLRequest` protocol. */
    TNLErrorCodeRequestOperationRequestNotProvided = 206,

    /** The `TNLRequest` could not be hydrated. The `NSUnderlyingError` key will be set. */
    TNLErrorCodeRequestOperationFailedToHydrateRequest = 207,

    /**
     The hydrated `TNLRequest` is not valid.
     The `NSUnderlyingError` will be set - usually a `TNLErrorCodeRequestBLAH` error.
     */
    TNLErrorCodeRequestOperationInvalidHydratedRequest = 208,

    /** There was an I/O error */
    TNLErrorCodeRequestOperationFileIOError = 209,

    /** There was an issue appending received data to memory */
    TNLErrorCodeRequestOperationAppendResponseDataError = 210,

    /**
     The underlying NSURLSession became invalid.
     If the invalidation is systemic, the `NSUnderlyingError` will be set.
     */
    TNLErrorCodeRequestOperationURLSessionInvalidated = 211,

    /** Authentication challenge was cancelled */
    TNLErrorCodeRequestOperationAuthenticationChallengeCancelled = 212,

    /**
     The request's `"Content-Encoding"` HTTP field was specified and it did not match the specified
     `TNLContentEncoder` on the `TNLRequestConfiguration`
     */
    TNLErrorCodeRequestOperationRequestContentEncodingTypeMissMatch = 213,

    /**
     The request's body failed to be encoded with the specified `TNLContentEncoder` on the
     `TNLRequestConfiguration`
     */
    TNLErrorCodeRequestOperationRequestContentEncodingFailed = 214,

    /**
     The response's body failed to be decoded with the matching `TNLContentDecoder` specified by
     `TNLRequestConfiguration`
     */
    TNLErrorCodeRequestOperationRequestContentDecodingFailed = 215,

    /** The operation could not authorize its request. */
    TNLErrorCodeRequestOperationFailedToAuthorizeRequest = 216,




    // Global Error Codes

    /** Generic global error */
    TNLErrorCodeGlobalGenericError = TNLErrorCodePageGlobal, // 300

    /**
     The URL host was blocked by the `TNLGlobalConfiguration`'s `TNLHostSanitizer`.
     `TNLErrorHostKey` will be set.
     */
    TNLErrorCodeGlobalHostWasBlocked = 301,




    // Other Error Codes

    /** Generic other error */
    TNLErrorCodeOtherGenericError = TNLErrorCodePageOther, // 9900

    /** The URL host was empty */
    TNLErrorCodeOtherHostCannotBeEmpty = 9901,
};

//! Convert `TNLErrorCode` to an `NSString`
FOUNDATION_EXTERN NSString * __nullable TNLErrorCodeToString(TNLErrorCode code);
//! Return `YES` if the `TNLErrorCode` is a terminal code and cannot be retried
FOUNDATION_EXTERN BOOL TNLErrorCodeIsTerminal(TNLErrorCode code);
//! Return `YES` if the `NSError` is a network security error, possibly due to Apple's _App Transport Security_
FOUNDATION_EXTERN BOOL TNLErrorIsNetworkSecurityError(NSError * __nullable error);
//! Create an `NSError` from a `TNLRequestOperationCancelSource`
FOUNDATION_EXTERN NSError * __nonnull TNLErrorFromCancelSource(id<TNLRequestOperationCancelSource> __nullable cancelSource,
                                                               NSError * __nullable underlyingError);

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

//! Convert an NSError to be NSSecureCoding safe (strip unsafe values from userInfo).  Only returns `nil` if provided _error_ is `nil`.
FOUNDATION_EXTERN NSError * __nullable TNLErrorToSecureCodingError(NSError * __nullable error);
//! Check if the given NSError objects are equal by just checking their domain+code & underlying errors the same way.  Both provided errors being `nil` will also count as being equal.
FOUNDATION_EXTERN BOOL TNLSecureCodingErrorsAreEqual(NSError * __nullable error1, NSError * __nullable error2);

NS_ASSUME_NONNULL_END

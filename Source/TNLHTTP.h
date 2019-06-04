//
//  TNLHTTP.h
//  TwitterNetworkLayer
//
//  Created on 6/9/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - HTTP Method

/**
 TNLHTTPMethod

 # HTTP Methods

 HTTP methods per http://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html

 Values correspond to the subsection number of Section 9 in RFC 2616.

 Ex: GET is Section 9.3

 ## Helper Functions

      // Convert TNLHTTPMethod to an NSString (ex: TNLHTTPMethodGET -> @"GET").
      // Unknown values will return nil.
      FOUNDATION_EXTERN NSString *TNLHTTPMethodToString(TNLHTTPMethod method);

      // Convert an NSString to TNLHTTPMethod (ex: @"GET" -> TNLHTTPMethodGET).
      // Unknown strings will return TNLHTTPMethodUnknown.
      FOUNDATION_EXTERN TNLHTTPMethod TNLHTTPMethodFromString(NSString *methodString);
 */
typedef NS_ENUM(NSInteger, TNLHTTPMethod) {
    TNLHTTPMethodUnknown    = 0,

    TNLHTTPMethodOPTIONS    = 2,
    TNLHTTPMethodGET        = 3,
    TNLHTTPMethodHEAD       = 4,
    TNLHTTPMethodPOST       = 5,
    TNLHTTPMethodPUT        = 6,
    TNLHTTPMethodDELETE     = 7,
    TNLHTTPMethodTRACE      = 8,
    TNLHTTPMethodCONNECT    = 9
};

FOUNDATION_EXTERN NSString * __nullable TNLHTTPMethodToString(TNLHTTPMethod method);
FOUNDATION_EXTERN TNLHTTPMethod TNLHTTPMethodFromString(NSString *methodString);

#pragma mark - HTTP Status Code

/**
 TNLHTTPStatusCode

 # HTTP Status Codes

 `TNLHTTPStatusCode` is ONLY for HTTP status codes.

 Do not introduce any non-HTTP status codes to this enum.

 The values are composed primarily from HTTP 1.1 RFC 2616 (section 10) http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
 but also contain values that are not ratified from @link http://en.wikipedia.org/wiki/List_of_HTTP_status_codes

 ## Helper Macros

      TNLHTTPStatusCodeIsInformational(code) // YES if the code is informational (1xx)
      TNLHTTPStatusCodeIsSuccess(code)       // YES if the code is success (2xx)
      TNLHTTPStatusCodeIsRedirection(code)   // YES if the code is redirect (3xx)
      TNLHTTPStatusCodeIsClientError(code)   // YES if the code is client error (4xx)
      TNLHTTPStatusCodeIsServerError(code)   // YES if the code is server error (5xx)
 */
typedef NS_ENUM(NSInteger, TNLHTTPStatusCode) {
    // 0 == None
    TNLHTTPStatusCodeNone = 0,

    // 1xx Informational
    TNLHTTPStatusCodeContinue = 100,
    TNLHTTPStatusCodeSwitchingProtocols = 101,
    TNLHTTPStatusCodeProcessing = 102,
    TNLHTTPStatusCodeCheckpoint = 103,

    // 2xx Success
    TNLHTTPStatusCodeOK = 200,
    TNLHTTPStatusCodeCreated = 201,
    TNLHTTPStatusCodeAccepted = 202,
    TNLHTTPStatusCodeNonAuthoritativeInformation = 203,
    TNLHTTPStatusCodeNoContent = 204,
    TNLHTTPStatusCodeResetContent = 205,
    TNLHTTPStatusCodePartialContent = 206,
    TNLHTTPStatusCodeMultiStatus = 207,
    TNLHTTPStatusCodeAlreadyReported = 208,

    TNLHTTPStatusCodeInstanceManipulationUsed = 226,

    // 3xx Redirection
    TNLHTTPStatusCodeMultipleChoices = 300,
    TNLHTTPStatusCodeMovedPermanently = 301,
    TNLHTTPStatusCodeFound = 302,
    TNLHTTPStatusCodeSeeOther = 303,
    TNLHTTPStatusCodeNotModified = 304,
    TNLHTTPStatusCodeUseProxy = 305,
    TNLHTTPStatusCodeSwitchProxy = 306,
    TNLHTTPStatusCodeTemporaryRedirect = 307,
    TNLHTTPStatusCodePermanentRedirect = 308,

    // 4xx Client Error
    TNLHTTPStatusCodeBadRequest = 400,
    TNLHTTPStatusCodeUnauthorized = 401,
    TNLHTTPStatusCodePaymentRequired = 402, // <<-- man I hope this never goes into effect
    TNLHTTPStatusCodeForbidden = 403,
    TNLHTTPStatusCodeNotFound = 404,
    TNLHTTPStatusCodeMethodNotAllowed = 405,
    TNLHTTPStatusCodeNotAcceptable = 406,
    TNLHTTPStatusCodeProxyAuthenticationRequired = 407,
    TNLHTTPStatusCodeRequestTimeout = 408,
    TNLHTTPStatusCodeConflict = 409,
    TNLHTTPStatusCodeGone = 410,
    TNLHTTPStatusCodeLengthRequired = 411,
    TNLHTTPStatusCodePreconditionFailed = 412,
    TNLHTTPStatusCodeRequestEntityTooLarge = 413,
    TNLHTTPStatusCodeRequestURITooLong = 414,
    TNLHTTPStatusCodeUnsupportedMediaType = 415,
    TNLHTTPStatusCodeRequestedRangeNotSatisfiable = 416,
    TNLHTTPStatusCodeExpectationFailed = 417,
    TNLHTTPStatusCodeImATeapot = 418, // <-- April Fool's
    TNLHTTPStatusCodeAuthenticationTimeout = 419,
    TNLHTTPStatusCodeEnhanceYourCalm = 420, // <-- the old 'Twitter' way for a 429
    TNLHTTPStatusCodeMisdirectedRequest = 421,
    TNLHTTPStatusCodeUnprocessableEntity = 422,
    TNLHTTPStatusCodeLocked = 423,
    TNLHTTPStatusCodeFailedDependency = 424,
    TNLHTTPStatusCodeUnorderedCollection = 425,
    TNLHTTPStatusCodeUpgradeRequired = 426,

    TNLHTTPStatusCodePreconditionRequired = 428,
    TNLHTTPStatusCodeTooManyRequests = 429,

    TNLHTTPStatusCodeRequestHeaderFieldsTooLarge = 431,

    TNLHTTPStatusCodeLoginTimeout = 440,

    TNLHTTPStatusCodeNoResponse = 444,

    TNLHTTPStatusCodeRetryWith = 449, /* retry with the missing required info */
    TNLHTTPStatusCodeBlockedByParentalControls = 450, /* Windows only a.t.m. */
    TNLHTTPStatusCodeUnavailableForLegalReasons = 451, /* Fahrenheit 451 */

    TNLHTTPStatusCodeSSLCertificateError = 495,
    TNLHTTPStatusCodeSSLCertificateRequired = 496,
    TNLHTTPStatusCodeHTTPRequestSentToHTTPSPort = 497,
    TNLHTTPStatusCodeInvalidToken = 498,
    TNLHTTPStatusCodeClientClosedRequest = 499,

    // 5xx Server Error
    TNLHTTPStatusCodeInternalServerError = 500,
    TNLHTTPStatusCodeNotImplemented = 501,
    TNLHTTPStatusCodeBadGateway = 502,
    TNLHTTPStatusCodeServiceUnavailable = 503,
    TNLHTTPStatusCodeGatewayTimeout = 504,
    TNLHTTPStatusCodeHTTPVersionNotSupported = 505,
    TNLHTTPStatusCodeVariantAlsoNegotiates = 506,
    TNLHTTPStatusCodeInsufficientStorage = 507,
    TNLHTTPStatusCodeLoopDetected = 508,
    TNLHTTPStatusCodeBandwidthLimitExceeded = 509,
    TNLHTTPStatusCodeNotExtended = 510,
    TNLHTTPStatusCodeNetworkAuthenticationRequired = 511,

    TNLHTTPStatusCodeUnknownError = 520, // Cloudflare
    TNLHTTPStatusCodeWebServerIsDown = 521, // Cloudflare
    TNLHTTPStatusCodeConnectionTimedOut = 522, // Cloudflare
    TNLHTTPStatusCodeOriginIsUnreachable = 523, // Cloudflare
    TNLHTTPStatusCodeATimeoutOccurred = 524, // Cloudflare
    TNLHTTPStatusCodeSSLHandshakeFailed = 525, // Cloudflare
    TNLHTTPStatusCodeInvalidSSLCertificate = 526, // Cloudflare
    TNLHTTPStatusCodeRailgunError = 527, // Cloudflare

    TNLHTTPStatusCodeSiteIsFrozen = 530,

    TNLHTTPStatusCodeNetworkReadTimeout = 598,
};

#define TNLHTTPStatusCodePageInformational      (100)
#define TNLHTTPStatusCodePageSuccess            (200)
#define TNLHTTPStatusCodePageRedirection        (300)
#define TNLHTTPStatusCodePageClientError        (400)
#define TNLHTTPStatusCodePageServerError        (500)

#define TNLHTTPStatusCodePageSize               (100)

#define TNLHTTPStatusCodeIsInformational(code)  (((code) / TNLHTTPStatusCodePageSize) == (TNLHTTPStatusCodePageInformational / TNLHTTPStatusCodePageSize))
#define TNLHTTPStatusCodeIsSuccess(code)        (((code) / TNLHTTPStatusCodePageSize) == (TNLHTTPStatusCodePageSuccess / TNLHTTPStatusCodePageSize))
#define TNLHTTPStatusCodeIsRedirection(code)    (((code) / TNLHTTPStatusCodePageSize) == (TNLHTTPStatusCodePageRedirection / TNLHTTPStatusCodePageSize))
#define TNLHTTPStatusCodeIsClientError(code)    (((code) / TNLHTTPStatusCodePageSize) == (TNLHTTPStatusCodePageClientError / TNLHTTPStatusCodePageSize))
#define TNLHTTPStatusCodeIsServerError(code)    (((code) / TNLHTTPStatusCodePageSize) == (TNLHTTPStatusCodePageServerError / TNLHTTPStatusCodePageSize))

NS_INLINE BOOL TNLHTTPStatusCodeIsDefinitiveSuccess(TNLHTTPStatusCode statusCode)
{
    if (!TNLHTTPStatusCodeIsSuccess(statusCode)) {
        return NO;
    }

    switch (statusCode) {
        case TNLHTTPStatusCodeAccepted:                     // 202
        case TNLHTTPStatusCodeNonAuthoritativeInformation:  // 203
        case TNLHTTPStatusCodeMultiStatus:                  // 207
        case TNLHTTPStatusCodeAlreadyReported:              // 208
        case TNLHTTPStatusCodeInstanceManipulationUsed:     // 226
        {
            return NO;
        }
        default:
        {
            // All other 2xx HTTP Status Codes are definitive
            return YES;
        }
    }
}

// HTTP Content-Type constants

FOUNDATION_EXTERN NSString * const TNLHTTPContentTypeJPEGImage;
FOUNDATION_EXTERN NSString * const TNLHTTPContentTypeQuicktimeVideo;
FOUNDATION_EXTERN NSString * const TNLHTTPContentTypeJSON;
FOUNDATION_EXTERN NSString * const TNLHTTPContentTypeTextPlain;
FOUNDATION_EXTERN NSString * const TNLHTTPContentTypeMultipartFormData;
FOUNDATION_EXTERN NSString * const TNLHTTPContentTypeOctetStream;
FOUNDATION_EXTERN NSString * const TNLHTTPContentTypeURLEncodedString;

//! Is the content type a textual format (limited to UTF8 [default] and ASCII currently), helpful for determining if something is printable or compressable
FOUNDATION_EXTERN BOOL TNLHTTPContentTypeIsTextual(NSString * __nullable contentType);

/**
 Enum for the different HTTP formats specified by the HTTP specification.

 From RFC2616 3.3.1 - http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3.1

    Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
    Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
    Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
    Sun Nov  6 08:49:37 +0000 1994 ; ANSI C's asctime() format, extended
 */
typedef NS_ENUM(NSInteger, TNLHTTPDateFormat)
{
    /** Unknown HTTP date format */
    TNLHTTPDateFormatUnknown = 0,
    /** RFC 822 date format */
    TNLHTTPDateFormatRFC822,
    /** RFC 850 date format */
    TNLHTTPDateFormatRFC850,
    /** ANSI C's date format */
    TNLHTTPDateFormatANSIC,
    /** ANSI C's date format, extended to have timezone support */
    TNLHTTPDateFormatANSICExt,
    /** Automatically choose the format */
    TNLHTTPDateFormatAuto = 0,
    /** RFC 1123 date format which is the same format as RFC 822 */
    TNLHTTPDateFormatRFC1123 = TNLHTTPDateFormatRFC822,
};

//! Convert an `NSString` to an `NSDate`, optionally decting the format
FOUNDATION_EXTERN NSDate * __nullable TNLHTTPDateFromString(NSString * __nullable string,
                                                            TNLHTTPDateFormat * __nullable detectedFormat);
//! Convert an `NSDate` to an `NSString` in the specified _format_
FOUNDATION_EXTERN NSString * __nullable TNLHTTPDateToString(NSDate * __nullable date,
                                                            TNLHTTPDateFormat format);

#if APPLEDOC
/**
 ## TNLHTTPContentType constants

 TNLHTTPContentType constants are a set of content type constants

 Use these constants when setting "Content-Type" values or MIME types.

 - `TNLHTTPContentTypeJPEGImage`
   - _@"image/jpeg"_
 - `TNLHTTPContentTypeQuicktimeVideo`
   - _@"video/quicktime"_
 - `TNLHTTPContentTypeJSON`
   - _@"application/json"_
 - `TNLHTTPContentTypeTextPlain`
   - _@"text/plain"_
 - `TNLHTTPContentTypeMultipartFormData`
   - _@"multipart/form-data"_

 ## TNLHTTPDateFromString

     NSDate *TNLHTTPDateFromString(NSString *string, TNLHTTPDateFormat *detectedFormat);

 Convert an `NSString` date to an `NSDate`.  Optionally provide a reference to a `TNLHTTPDateFormat`
 to have the detected date format returned too.

 ## TNLHTTPDateToString

     NSString *TNLHTTPDateToString(NSDate *date, TNLHTTPDateFormat format);

 Convert an `NSDate` to an `NSString` date formatted string.  Provide the _format_ desired or
 `TNLHTTPDateFormatAuto` or `0` to use the default format.
 */
@interface TNLHTTP
@end
#endif

NS_ASSUME_NONNULL_END

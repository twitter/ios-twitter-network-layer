//
//  TNLError.m
//  TwitterNetworkLayer
//
//  Created on 7/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLError.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const TNLErrorDomain = @"com.twitter.tnl.error.domain";
NSString * const TNLContentEncodingErrorDomain = @"com.twitter.tnl.content.encoding.error.domain";

NSString * const TNLErrorTimeoutTagsKey = @"timeoutTags";
NSString * const TNLErrorCancelSourceKey = @"cancelSource";
NSString * const TNLErrorCancelSourceDescriptionKey = @"cancelSourceDescription";
NSString * const TNLErrorCancelSourceLocalizedDescriptionKey = @"localizedCancelSourceDescription";
NSString * const TNLErrorCodeStringKey = @"TNLError.string";
NSString * const TNLErrorHostKey = @"host";
NSString * const TNLErrorRequestKey = @"request";
NSString * const TNLErrorProtectionSpaceHostKey = @"protectionSpaceHost";
NSString * const TNLErrorCertificateChainDescriptionsKey = @"certificateChainDescriptions";
NSString * const TNLErrorAuthenticationChallengeMethodKey = @"authenticationChallengeMethod";

NSString *TNLErrorCodeToString(TNLErrorCode code)
{
#define ERROR_CASE(m) \
case TNLErrorCode##m : { return @"" #m ; }

    switch (code) {

            ERROR_CASE(RequestGenericError)
            ERROR_CASE(RequestInvalid)
            ERROR_CASE(RequestInvalidURL)
            ERROR_CASE(RequestInvalidHTTPMethod)
            ERROR_CASE(RequestHTTPBodyCannotBeSetForDownload)
            ERROR_CASE(RequestInvalidBackgroundRequest)

            ERROR_CASE(RequestOperationGenericError)
            ERROR_CASE(RequestOperationCancelled)
            ERROR_CASE(RequestOperationOperationTimedOut)
            ERROR_CASE(RequestOperationAttemptTimedOut)
            ERROR_CASE(RequestOperationIdleTimedOut)
            ERROR_CASE(RequestOperationCallbackTimedOut)
            ERROR_CASE(RequestOperationRequestNotProvided)
            ERROR_CASE(RequestOperationFailedToHydrateRequest)
            ERROR_CASE(RequestOperationInvalidHydratedRequest)
            ERROR_CASE(RequestOperationFileIOError)
            ERROR_CASE(RequestOperationAppendResponseDataError)
            ERROR_CASE(RequestOperationURLSessionInvalidated)
            ERROR_CASE(RequestOperationAuthenticationChallengeCancelled)
            ERROR_CASE(RequestOperationRequestContentEncodingTypeMissMatch)
            ERROR_CASE(RequestOperationRequestContentEncodingFailed)
            ERROR_CASE(RequestOperationRequestContentDecodingFailed)
            ERROR_CASE(RequestOperationFailedToAuthorizeRequest)

            ERROR_CASE(GlobalGenericError)
            ERROR_CASE(GlobalHostWasBlocked)

            ERROR_CASE(OtherGenericError)
            ERROR_CASE(OtherHostCannotBeEmpty)

        case TNLErrorCodeUnknown:
            return nil;
    }

    TNLAssertNever();
    return nil;

#undef ERROR_CASE
}

BOOL TNLErrorCodeIsTerminal(TNLErrorCode code)
{
    if (TNLErrorCodeIsRequestError(code)) {
        return YES;
    }

    switch (code) {
        case TNLErrorCodeUnknown:
            return NO;
        case TNLErrorCodeRequestGenericError:
        case TNLErrorCodeRequestInvalid:
        case TNLErrorCodeRequestInvalidURL:
        case TNLErrorCodeRequestInvalidHTTPMethod:
        case TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload:
        case TNLErrorCodeRequestInvalidBackgroundRequest:
            return YES;
        case TNLErrorCodeRequestOperationCancelled:
        case TNLErrorCodeRequestOperationOperationTimedOut:
        case TNLErrorCodeRequestOperationRequestNotProvided:
        case TNLErrorCodeRequestOperationFailedToHydrateRequest:
        case TNLErrorCodeRequestOperationInvalidHydratedRequest:
        case TNLErrorCodeRequestOperationFailedToAuthorizeRequest:
            return YES;
        case TNLErrorCodeOtherHostCannotBeEmpty:
            return YES;
        case TNLErrorCodeRequestOperationGenericError:
        case TNLErrorCodeRequestOperationAttemptTimedOut:
        case TNLErrorCodeRequestOperationIdleTimedOut:
        case TNLErrorCodeRequestOperationCallbackTimedOut:
        case TNLErrorCodeRequestOperationFileIOError:
        case TNLErrorCodeRequestOperationAppendResponseDataError:
        case TNLErrorCodeRequestOperationURLSessionInvalidated:
        case TNLErrorCodeRequestOperationAuthenticationChallengeCancelled:
        case TNLErrorCodeRequestOperationRequestContentEncodingFailed:
        case TNLErrorCodeRequestOperationRequestContentEncodingTypeMissMatch:
        case TNLErrorCodeRequestOperationRequestContentDecodingFailed:
        case TNLErrorCodeGlobalGenericError:
        case TNLErrorCodeGlobalHostWasBlocked:
        case TNLErrorCodeOtherGenericError:
            return NO;
    }

    return NO;
}

BOOL TNLErrorIsNetworkSecurityError(NSError * __nullable error)
{
    NSString * const domain = error.domain;
    NSInteger code = error.code;
    if ([domain isEqualToString:TNLErrorDomain] && TNLErrorCodeRequestOperationAuthenticationChallengeCancelled == code) {
        // auth challenge failed
        return YES;
    }

    if (![domain isEqualToString:NSURLErrorDomain] && ![domain isEqualToString:(NSString *)kCFErrorDomainCFNetwork]) {
        // not an internet failure
        return NO;
    }

    // Conveniently, NSURL errors and CFNetwork errors share the same error code values

    if (-1022 == code) {
        // Insecure request violates ATS
        return YES;
    } else if (-1200 == code) {
        // skip! - this is SSL connection failure
        // which is a network failure, not a security failure
    } else if (code <= -1201 && code >= -1206) {
        // SSL error
        return YES;
    } else if (-2000 == code) {

#if !TARGET_OS_WATCH
        // cannot load from network - is it due to SSL?

        if (nil != error.userInfo[(NSString *)kCFStreamPropertySSLPeerTrust]) {
            // short cut - we have a "trust" which implicates network security
            return YES;
        }

        // Some network errors can be underpinned by CFStream errors,
        // which are not wrapped in an `NSError`,
        // so we can look at the userInfo for specific keys
        // (namely _kCFStreamErrorDomainKey and _kCFStreamErrorDomainCode)
        id domainNumber = error.userInfo[@"_kCFStreamErrorDomainKey"];
        if ([domainNumber respondsToSelector:@selector(intValue)]) {
            if (kCFStreamErrorDomainSSL == [domainNumber intValue]) {
                // It is an SSL error, treat as security error
                // NOTE: there is a more specific subset of error codes which we are ignoring (see Security/SecureTransport.h)
                return YES;
            }
        }
#endif // !WATCH
    }

    NSError * const underlyingError = error.userInfo[NSUnderlyingErrorKey];
    if (underlyingError) {
        // recurse to see if the underlying error is network security related
        return TNLErrorIsNetworkSecurityError(underlyingError);
    }

    return NO;
}

#pragma mark - NSError helpers

NSArray<NSNumber *> *TNLStandardRetriableURLErrorCodes()
{
    return @[
             @(NSURLErrorUnknown),                          // -1
             @(NSURLErrorTimedOut),                         // -1001
             @(NSURLErrorCannotFindHost),                   // -1003
             @(NSURLErrorCannotConnectToHost),              // -1004
             @(NSURLErrorNetworkConnectionLost),            // -1005
             @(NSURLErrorDNSLookupFailed),                  // -1006
             @(NSURLErrorHTTPTooManyRedirects),             // -1007
             @(NSURLErrorResourceUnavailable),              // -1008
             @(NSURLErrorNotConnectedToInternet),           // -1009
             @(NSURLErrorRedirectToNonExistentLocation),    // -1010
             @(NSURLErrorInternationalRoamingOff),          // -1018
             @(NSURLErrorCallIsActive),                     // -1019
             @(NSURLErrorDataNotAllowed),                   // -1020
             @(NSURLErrorSecureConnectionFailed),           // -1200
             @(NSURLErrorCannotLoadFromNetwork),            // -2000
             ];
}

NSArray<NSNumber *> *TNLStandardRetriablePOSIXErrorCodes()
{
    return @[
             @(EPIPE),          //      32    /* Broken pipe */
             @(ENETDOWN),       //      50    /* Network is down */
             @(ENETUNREACH),    //      51    /* Network is unreachable */
             @(ENETRESET),      //      52    /* Network dropped connection on reset */
             @(ECONNABORTED),   //      53    /* Software caused connection abort */
             @(ECONNRESET),     //      54    /* Connection reset by peer */
             @(ENOBUFS),        //      55    /* No buffer space available */
             @(EISCONN),        //      56    /* Socket is already connected */
             @(ENOTCONN),       //      57    /* Socket is not connected */
             @(ESHUTDOWN),      //      58    /* Can't send after socket shutdown */
             @(ETOOMANYREFS),   //      59    /* Too many references: can't splice */
             @(ETIMEDOUT),      //      60    /* Connection timed out */
             @(ECONNREFUSED),   //      61    /* Connection refused */
             @(EHOSTDOWN),      //      64    /* Host is down */
             @(EHOSTUNREACH),   //      65    /* No route to host */
             ];
}

NS_ASSUME_NONNULL_END


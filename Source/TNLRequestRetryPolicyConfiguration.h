//
//  TNLRequestRetryPolicyConfiguration.h
//  TwitterNetworkLayer
//
//  Created on 5/26/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLRequestOperation;

/**
 Configuration object for use with `TNLRequestRetryPolicyProvider` instances.

 A `TNLRequestRetryPolicyConfiguration` makes it simple to check if a `TNLRequestOperation` can be retried based on configurable criteria.  It is not very useful for more dynamic policies, but provides a very strong mechanism for policies to have a static set of criteria to be met before permitting a retry.

 See also: `TNLMutableRequestRetryPolicyConfiguration`
 See also: `TNLStandardRetriableURLErrorCodes()` and `TNLStandardRetriablePOSIXErrorCodes()`
 */
@interface TNLRequestRetryPolicyConfiguration : NSObject <NSCopying, NSMutableCopying>

/**
 A default configuration
 @return a configuration that permits retries on HTTP `GET` requests that return `503`
 */
+ (instancetype)defaultConfiguration; // GET on 503

/**
 A standard configuration more advanced than the default configuration
 @return a configuration that permits retries on HTTP `GET` requests that either return `503`, or
 fail with a `NSURLErrorDomain` error from `TNLStandardRetriableURLErrorCodes()`, or
 fail with a `NSPOSIXErrorDomain` error from `TNLStandardRetriablePOSIXErrorCodes()`
 */
+ (instancetype)standardConfiguration; // GET w/ 503, TNLStandardRetriableURLErrorCodes() or TNLStandardRetriablePOSIXErrorCodes()

/**
 Default initializer (designated)

 @param methods     An array of HTTP Methods that retries are permitted for.  Must be an array of `NSString` objects (ex: `@"GET"`) and/or `NSNumber` objects wrapping `TNLHTTPMethod` enum values.
 @param statusCodes An array of HTTP Status Codes that retries are permitted for.  Must be an array of `NSNumber` objects wrapping `TNLHTTPStatusCode` enum values.
 @param URLErrorCodes An array of `NSURLErrorDomain` error codes that retries are permitted for.
 @param POSIXErrorCodes An array of `NSPOSIXErrorDomain` error codes that retries are permitted for.

 @return a new configuration
 */
- (instancetype)initWithRetriableMethods:(nullable NSArray *)methods
                             statusCodes:(nullable NSArray<NSNumber *> *)statusCodes
                           URLErrorCodes:(nullable NSArray<NSNumber *> *)URLErrorCodes
                         POSIXErrorCodes:(nullable NSArray<NSNumber *> *)POSIXErrorCodes;

/**
 An initializer that permits all HTTP Methods to be retried.

 See `initWithRetriableMethods:statusCodes:URLErrorCodes:POSIXErrorCodes:`
 */
- (instancetype)initWithAllMethodsRetriableAndRetriableStatusCodes:(nullable NSArray<NSNumber *> *)statusCodes
                                                     URLErrorCodes:(nullable NSArray<NSNumber *> *)URLErrorCodes
                                                   POSIXErrorCodes:(nullable NSArray<NSNumber *> *)POSIXErrorCodes;

/**
 Check if an HTTP Method is retriable for the receiver

 @param method The HTTP Method to test
 @return `YES` if _method_ is retriable, otherwise `NO`
 */
- (BOOL)methodCanBeRetried:(TNLHTTPMethod)method;

/**
 Check if an HTTP Status Code is retriable for the receiver

 @param code The HTTP Status Code to test
 @return `YES` if _code_ is retriable, otherwise `NO`
 */
- (BOOL)statusCodeCanBeRetried:(TNLHTTPStatusCode)code;

/**
 Check if an `NSURLErrorDomain` error code is retriable for the receiver

 @param code The error code to test
 @return `YES` if _code_ is retriable, otherwise `NO`
 */
- (BOOL)URLErrorCodeCanBeRetried:(NSInteger)code;

/**
 Check if an `NSPosixErrorDomain` error code (from `<sys/errno.h>`) is retriable for the receiver

 @param code The error code to test
 @return `YES` if the _code_ is retriable, otherwise `NO`
 */
- (BOOL)POSIXErrorCodeCanBeRetried:(int)code;

// Override in subclass to extend configurability

/**
 Check if an operation with a `TNLResponse` can be retried

 Calls all related `*CanBeRetried:` methods.
 `methodCanBeRetried:` with the _response.info.finalURLRequest.HTTPMethod_ object's HTTP Method.
 `statusCodeCanBeRetried:` with _requestOperation.response.info.statusCode_.
 `URLErrorCodeCanBeRetried:` or `POSIXErrorCanBeRetried:` based on the _requestOperation.operationError_

 @param response The operation's `TNLResponse` to test

 @return `YES` if it is retriable, otherwise `NO`
 */
- (BOOL)requestCanBeRetriedForResponse:(TNLResponse *)response;

@end

/**
  The mutable version of `TNLRequestRetryPolicyConfiguration`

  See `TNLRequestRetryPolicyConfiguration`
 */
@interface TNLMutableRequestRetryPolicyConfiguration : TNLRequestRetryPolicyConfiguration

/** Set whether a specific HTTP Method can be retried */
- (void)setMethod:(TNLHTTPMethod)method canBeRetried:(BOOL)canRetry;
/** Set whether a specific HTTP Status Code can be retried */
- (void)setStatusCode:(TNLHTTPStatusCode)code canBeRetried:(BOOL)canRetry;
/** Set whether a specific `NSURLErrorDomain` error code can be retried */
- (void)setURLErrorCode:(NSInteger)code canBeRetried:(BOOL)canRetry;
/** Set whether a specific `NSPOSIXErrorDomain` error code can be retried */
- (void)setPOSIXErrorCode:(int)code canBeRetried:(BOOL)canRetry;

/** Replaces existing list of HTTP Methods that can be retried. */
- (void)setMethodsThatCanBeRetried:(nullable NSArray *)methods;
/** Replaces existing list of HTTP Status Codes that can be retried. */
- (void)setStatusCodesThatCanBeRetried:(nullable NSArray<NSNumber *> *)codes;
/** Replace existing list of `NSURLErrorDomain` error codes that can be retried. */
- (void)setURLErrorCodesThatCanBeRetried:(nullable NSArray<NSNumber *> *)codes;
/** Replace existing list of `NSPOSIXErrorDomain` error codes that can be retried. */
- (void)setPOSIXErrorCodesThatCanBeRetried:(nullable NSArray<NSNumber *> *)codes;

@end

NS_ASSUME_NONNULL_END

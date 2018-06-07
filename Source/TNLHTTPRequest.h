//
//  TNLHTTPRequest.h
//  TwitterNetworkLayer
//
//  Created on 2/28/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLRequest.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Concrete implementation of `TNLRequest` protocol.

 Pairs with `TNLMutableHTTPRequest`
 */
@interface TNLHTTPRequest : NSObject <TNLRequest, NSMutableCopying, NSSecureCoding, NSCopying>

/** init with an `NSURL` */
- (instancetype)initWithURL:(nullable NSURL *)url;
/** init with an `NSURLRequest` */
- (instancetype)initWithURLRequest:(nullable NSURLRequest *)request;
/** init with an `NSURLRequest` and a file path for the HTTP body */
- (instancetype)initWithURLRequest:(nullable NSURLRequest *)request
                  HTTPBodyFilePath:(nullable NSString *)bodyFilePath;
/**
 init with arguments (designated initializer)

 For HTTP POST, provide only 1 of `body`, `bodyStream` or `bodyFilePath`

 @param url          the `NSURL`
 @param method       the `TNLHTTPMethod`
 @param fields       the HTTP Header fields
 @param body         the HTTP POST body
 @param bodyStream   the HTTP POST body as a stream
 @param bodyFilePath the HTTP POST body as a file

 @return a new concrete `TNLHTTPRequest`
 */
- (instancetype)initWithURL:(nullable NSURL *)url
            HTTPMethodValue:(TNLHTTPMethod)method
           HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields
                   HTTPBody:(nullable NSData *)body
             HTTPBodyStream:(nullable NSInputStream *)bodyStream
           HTTPBodyFilePath:(nullable NSString *)bodyFilePath NS_DESIGNATED_INITIALIZER;

/** Convenience POST request constructor */
+ (instancetype)POSTRequestWithURL:(nullable NSURL *)url
                  HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields
                          HTTPBody:(nullable NSData *)body;
/** Convenience POST request constructor */
+ (instancetype)POSTRequestWithURL:(nullable NSURL *)url
                  HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields
                    HTTPBodyStream:(nullable NSInputStream *)bodyStream;
/** Convenience POST request constructor */
+ (instancetype)POSTRequestWithURL:(nullable NSURL *)url
                  HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields
                  HTTPBodyFilePath:(nullable NSString *)bodyFilePath;

/** Convenience GET request constructor */
+ (nonnull instancetype)GETRequestWithURL:(nullable NSURL *)url
                         HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields;
/** Convenience PUT request constructor */
+ (nonnull instancetype)PUTRequestWithURL:(nullable NSURL *)url
                         HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields;
/** Convenience DELETE request constructor */
+ (nonnull instancetype)DELETERequestWithURL:(nullable NSURL *)url
                            HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields;
/** Convenience HEAD request constructor */
+ (nonnull instancetype)HEADRequestWithURL:(nullable NSURL *)url
                          HTTPHeaderFields:(nullable NSDictionary<NSString *, NSString *> *)fields;

/** Convenience constructor for building a concrete `TNLHTTPRequest` with an opaque `id<TNLRequest>` */
+ (nonnull instancetype)HTTPRequestWithRequest:(nullable id<TNLRequest>)request;


/** See `TNLRequest` protocol */
@property (nonatomic, readonly, nullable) NSURL *URL;
/** See `TNLRequest` protocol */
@property (nonatomic, readonly) TNLHTTPMethod HTTPMethodValue;
/**
 See `TNLRequest` protocol
 @note A copy is not made so it is the caller's responsibility to NOT mutate the provided body after
 it has been set on the concrete `TNLHTTPRequest`.  It's really just common sense.
 */
@property (nonatomic, readonly, nullable) NSData *HTTPBody;
/** See `TNLRequest` protocol */
@property (nonatomic, readonly, nullable) NSInputStream *HTTPBodyStream;
/** See `TNLRequest` protocol */
@property (nonatomic, readonly, nullable) NSString *HTTPBodyFilePath;
/** See `TNLRequest` protocol */
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields;


/**
 Convenience method to access a case-insensitive HTTP Header field
 @param field The case-insensitive HTTP Header field to look up
 @return the HTTP Header value matching the provided _field_
 */
- (nullable NSString *)valueForHTTPHeaderField:(nonnull NSString *)field;

@end

/**
 Concrete mutable implementation of `TNLRequest` protocol.

 Pairs with `TNLHTTPRequest`
 */
@interface TNLMutableHTTPRequest : TNLHTTPRequest

@property (nonatomic, readwrite, nullable) NSURL *URL;
@property (nonatomic, readwrite) TNLHTTPMethod HTTPMethodValue;
@property (nonatomic, readwrite, nullable) NSData *HTTPBody;
@property (nonatomic, readwrite, nullable) NSInputStream *HTTPBodyStream;
@property (nonatomic, copy, nullable) NSString *HTTPBodyFilePath;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields;

/** Replace the _value_ for an HTTP Header field (_field_ is case-insensitive) */
- (void)setValue:(nonnull NSString *)value forHTTPHeaderField:(nonnull NSString *)field;
/** Remove all values for an HTTP Header field (_field_ is case-insensitive) */
- (void)removeAllValuesForHTTPHeaderField:(nonnull NSString *)field;

@end

NS_ASSUME_NONNULL_END

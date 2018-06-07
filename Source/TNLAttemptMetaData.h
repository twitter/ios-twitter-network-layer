//
//  TNLAttemptMetaData.h
//  TwitterNetworkLayer
//
//  Created on 1/16/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 `TNLAttemptMetaData` encapsulates metadata for the request and response. Not all fields are
 guaranteed to be provided, which is why each field provides a `hasField` method. Categories are
 used to provide a degree of organization.
 */
@interface TNLAttemptMetaData : NSObject <NSSecureCoding>
/** The meta data as a dictionary */
- (NSDictionary<NSString *, id> *)metaDataDictionary;
@end

/**
 HTTP related meta data. These fields apply for all requests serviced by TNL.
 */
@interface TNLAttemptMetaData (HTTP)

/** The HTTP version.  Usually `@"1.1"`. TODO: replace this with "protocol version" */
@property (nonatomic, copy, readonly, nullable) NSString *HTTPVersion;
- (BOOL)hasHTTPVersion;

/**
 The number of bytes received in the response body at OSI layer 8.
 This is the decompressed size, not the compressed size which would be layer 4.
 */
@property (nonatomic, readonly) SInt64 layer8BodyBytesReceived;
- (BOOL)hasLayer8BodyBytesReceived;

/** The number of bytes transmitted in the request body at OSI layer 8. */
@property (nonatomic, readonly) SInt64 layer8BodyBytesTransmitted;
- (BOOL)hasLayer8BodyBytesTransmitted;

/** The time in milliseconds that the server took to response.  0 indicates unknown. */
@property (nonatomic, readonly) SInt64 serverResponseTime;
- (BOOL)hasServerResponseTime;

/** The local cache was used to retrieve the response */
@property (nonatomic, readonly) BOOL localCacheHit;
- (BOOL)hasLocalCacheHit;

/** Expected MD5 Hash of the response body */
@property (nonatomic, readonly, nullable) NSData *expectedMD5Hash;
- (BOOL)hasExpectedMD5Hash;

/** The MD5 Hash of the response body */
@property (nonatomic, readonly, nullable) NSData *MD5Hash;
- (BOOL)hasMD5Hash;

/** The Content-Length in the request */
@property (nonatomic, readonly) SInt64 requestContentLength;
- (BOOL)hasRequestContentLength;

/** Time it took to encode the request body */
@property(nonatomic, readonly) NSTimeInterval requestEncodingLatency;
- (BOOL)hasRequestEncodingLatency;

/** Request's original Content-Length before encoding */
@property (nonatomic, readonly) SInt64 requestOriginalContentLength;
- (BOOL)hasRequestOriginalContentLength;

/** The Content-Length in the response */
@property (nonatomic, readonly) SInt64 responseContentLength;
- (BOOL)hasResponseContentLength;

/** Time it took to decode the response body (if known) */
@property (nonatomic, readonly) NSTimeInterval responseDecodingLatency;
- (BOOL)hasResponseDecodingLatency;

/** The Content-Length of the response body after being decoded */
@property (nonatomic, readonly) SInt64 responseDecodedContentLength;
- (BOOL)hasResponseDecodedContentLength;

/** The estimated duration that it took to receive all the body bytes */
@property (nonatomic, readonly) NSTimeInterval responseContentDownloadDuration;
- (BOOL)hasResponseContentDownloadDuration;

@end

NS_ASSUME_NONNULL_END

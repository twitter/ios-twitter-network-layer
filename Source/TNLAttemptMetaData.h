//
//  TNLAttemptMetaData.h
//  TwitterNetworkLayer
//
//  Created on 1/16/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLPriority.h>
#import <TwitterNetworkLayer/TNLRequestConfiguration.h>

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

/** The session identifier used for the network transaction (translates to an `NSURLSession` instance) */
@property (nonatomic, copy, readonly, nullable) NSString *sessionId;
- (BOOL)hasSessionId;

/** The latency between when the `resume` was called on the underlying task and when the task actually began fetching */
@property (nonatomic, readonly) NSTimeInterval taskResumeLatency;
- (BOOL)hasTaskResumeLatency;

/** The priority that `resume` was called with, indicative of the priority the task will execute with */
@property (nonatomic, readonly) TNLPriority taskResumePriority;
- (BOOL)hasTaskResumePriority;

/**
 The latency between task completion and task metrics being delivered.
 Task metrics, per docs, are to be delivered BEFORE the completion callback.
 However, due to radar #27098270, this order can end up being mixed up.
 The presence of this meta data indicates the issue was encountered.

 Apple documentation in `NSURLSession.h`:

     // Sent as the last message related to a specific task.  Error may be
     // nil, which implies that no error occurred and this task is complete.
     - (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error;
*/
@property (nonatomic, readonly) NSTimeInterval taskMetricsAfterCompletionLatency;
- (BOOL)hasTaskMetricsAfterCompletionLatency;

/**
 The latency between the task completion and meta data being constructed (actual completion)
 when there are no task metrics delivered.
 Task metrics, per docs, are to be delivered BEFORE the completion callback.
 However, due to radar #27098270, this order can end up being mixed up.
 The presence of this meta data indicates the issue was encountered AND the metrics did not come sufficiently soon enough.

 Apple documentation in `NSURLSession.h`:

     // Sent as the last message related to a specific task.  Error may be
     // nil, which implies that no error occurred and this task is complete.
     - (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error;
 */
@property (nonatomic, readonly) NSTimeInterval taskWithoutMetricsCompletionLatency;
- (BOOL)hasTaskWithoutMetricsCompletionLatency;


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

/** The hash alogorithm of the response body */
@property (nonatomic, readonly) TNLResponseHashComputeAlgorithm responseBodyHashAlgorithm;
- (BOOL)hasResponseBodyHashAlgorithm;

/** The hash of the response body */
@property (nonatomic, readonly, nullable) NSData *responseBodyHash;
- (BOOL)hasResponseBodyHash;

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

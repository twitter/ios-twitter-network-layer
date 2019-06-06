//
//  TNLAttemptMetaData_Project.h
//  TwitterNetworkLayer
//
//  Created on 1/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TNLAttemptMetaData.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

// Instructions for adding a new field:
// 1. Add new property and ...IsSet method and helpful comment to TNLAttemptMetaData.h.
// 2. Add new row to HTTP_FIELDS in TNLAttemptMetaData_Project.h (below).
// 3. You're done.
//
// OBJECT_FIELD(fieldName, fieldNameUpperCase, fieldType, modifiers)
// - used for object types, like NSString or other classes.
// - parameters:
//   fieldName: name of field, must match property name.
//   fieldNameUpperCase: same as fieldName but first letter must be upper-case.
//   fieldType: Objective-C type of the field.
//
// PRIMITIVE_FIELD(fieldName, fieldNameUpperCase, fieldType, getterMethod)
// - used for primitive types, like integers, doubles, or enumerations.
// - parameters:
//   fieldName: name of field, must match property name.
//   fieldNameUpperCase: same as fieldName but first letter must be upper-case.
//   fieldType: Objective-C type of the field.
//   getterMethod: appropriate getter method in NSNumber. Use unsignedIntValue for enums.

// List of all properties in TNLAttemptMetaData (HTTP)
// See TNLAttemptMetadata.h for concrete properties and descriptions.
#define HTTP_FIELDS() \
OBJECT_FIELD(HTTPVersion, HTTPVersion, NSString) \
PRIMITIVE_FIELD(layer8BodyBytesReceived, Layer8BodyBytesReceived, SInt64, longLongValue) \
PRIMITIVE_FIELD(layer8BodyBytesTransmitted, Layer8BodyBytesTransmitted, SInt64, longLongValue) \
PRIMITIVE_FIELD(serverResponseTime, ServerResponseTime, SInt64, longLongValue) \
PRIMITIVE_FIELD(localCacheHit, LocalCacheHit, BOOL, boolValue) \
PRIMITIVE_FIELD(responseBodyHashAlgorithm, ResponseBodyHashAlgorithm, TNLResponseHashComputeAlgorithm, integerValue) \
OBJECT_FIELD(responseBodyHash, ResponseBodyHash, NSData) \
OBJECT_FIELD(sessionId, SessionId, NSString) \
\
PRIMITIVE_FIELD(taskResumeLatency, TaskResumeLatency, NSTimeInterval, doubleValue) \
PRIMITIVE_FIELD(taskResumePriority, TaskResumePriority, TNLPriority, integerValue) \
PRIMITIVE_FIELD(taskMetricsAfterCompletionLatency, TaskMetricsAfterCompletionLatency, NSTimeInterval, doubleValue) \
PRIMITIVE_FIELD(taskWithoutMetricsCompletionLatency, TaskWithoutMetricsCompletionLatency, NSTimeInterval, doubleValue) \
\
PRIMITIVE_FIELD(requestContentLength, RequestContentLength, SInt64, longLongValue) \
PRIMITIVE_FIELD(requestEncodingLatency, RequestEncodingLatency, NSTimeInterval, doubleValue) \
PRIMITIVE_FIELD(requestOriginalContentLength, RequestOriginalContentLength, SInt64, longLongValue) \
\
PRIMITIVE_FIELD(responseContentLength, ResponseContentLength, SInt64, longLongValue) \
PRIMITIVE_FIELD(responseDecodingLatency, ResponseDecodingLatency, NSTimeInterval, doubleValue) \
PRIMITIVE_FIELD(responseDecodedContentLength, ResponseDecodedContentLength, SInt64, longLongValue) \
PRIMITIVE_FIELD(responseContentDownloadDuration, ResponseContentDownloadDuration, NSTimeInterval, doubleValue) \

// Generate read/write properties for all fields

#define OBJECT_FIELD(field, fieldUpper, type) \
@property (nonatomic, copy, nullable) type *field; \
- (BOOL)has##fieldUpper; \

#define PRIMITIVE_FIELD(field, fieldUpper, type, getter) \
@property (nonatomic) type field; \
- (BOOL)has##fieldUpper; \

@interface TNLAttemptMetaData (HTTP_Project)
HTTP_FIELDS()
@end

@interface TNLAttemptMetaData (Project)
- (instancetype)initWithMetaDataDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;
/** Finalizes the metadata.  Called during `TNLResponse` init.  Cannot call `addMetaDataInfo:` afterwards */
- (void)finalizeMetaData;
@end

#undef OBJECT_FIELD
#undef PRIMITIVE_FIELD

NS_ASSUME_NONNULL_END

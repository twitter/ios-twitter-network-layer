//
//  TNLMultipartFormData.h
//  TwitterNetworkLayer
//
//  Created on 8/22/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLRequest.h"

/*
    TODO:[nobrien] - this code is not versatile enough for any multipart/form-data request.
    It is too specialized to how Twitter utilizes multipart POSTs.

    http://www.w3.org/TR/html401/interact/forms.html#h-17.13.4

    Therefore, this should only be considered as an example, not a reusable component in TNL itself.
 */

@class TNLXFormDataEntry;
@protocol TNLRequestHydrater;

FOUNDATION_EXTERN NSString * const TNLXMultipartFormDataErrorDomain;

typedef NS_ENUM(NSInteger, TNLXMultipartFormDataErrorCode) {
    /** Generic Multipart Form Data error */
    TNLXMultipartFormDataErrorCodeGenericError = 0,
    /** The `boundary` was invalid. `[TNLXMultipartFormDataRequest boundary]` */
    TNLXMultipartFormDataErrorCodeInvalidBoundary,
    /** An entry was invalid. `[TNLXMultipartFormDataRequest addFormData:]` */
    TNLXMultipartFormDataErrorCodeInvalidFormDataEntry,
};

/**
 Multipart Form Data Upload Format

 Used with `[TNLMultipartFormDataRequest generateRequestWithUploadFormat:error:]`
 */
typedef NS_ENUM(NSInteger, TNLXMultipartFormDataUploadFormat)
{
    /** The request should POST the data from a file on disk.  Useful for background requests. */
    TNLXMultipartFormDataUploadFormatFile = 0,
    /** The request should POST the data from data in memory. */
    TNLXMultipartFormDataUploadFormatData,
    // TODO:[nobrien] - TNLMultipartFormDataUploadFormatStream,

    /** Default */
    TNLXMultipartFormDataUploadFormatDefault = TNLXMultipartFormDataUploadFormatFile,
};

/**
 Request object conforming to `TNLRequest` for Multipart Form Data

 Provide a `TNLMultipartFormDataRequest` to your `TNLRequestOperationQueue` of choice
 to create a `TNLRequestOperation` and have the `TNLRequestHydrater`
 make a hydrated request with `generateRequestWithUploadFormat:error:`.

 Alternatively, you can provide the `TNLRequest` from the `generateRequestWithUploadFormat:error:`
 directly to the `TNLRequestOperationQueue` if you want to avoid having a `TNLRequestHydrater`, though the
 former mechanism is the recommended mechanism.
 */
@interface TNLXMultipartFormDataRequest : NSObject <TNLRequest, NSCopying> // TODO:[nobrien] - <NSCoding>

/// `TNLHTTPMethodPOST`
@property (nonatomic, readonly) TNLHTTPMethod HTTPMethodValue;
/// The URL of the request. See `TNLHTTPRequest`
@property (nonatomic, readwrite) NSURL *URL;
/// The HTTP header fields fo the request.  See `TNLHTTPRequest`
@property (nonatomic, copy) NSDictionary *allHTTPHeaderFields;
/**
 The boundary for the multipart form data.

 If not set, this value will be generated.

 @note Only Alpha, Numeric, Period, Dash and Underscore are valid characters.
 If the set value is invalid, an error will occur during `[TNLMultipartFormDataRequest generateRequestWithUploadFormat:error:]`
 */
@property (nonatomic, copy) NSString *boundary;

/**
 Add a form data entry to the multipart form data request.
 @param formData The form data entry to add
 @discussion __See Also:__ `TNLFormDataEntry`
 */
- (void)addFormData:(TNLXFormDataEntry *)formData;
/**
 @return The number of form data entries in the request
 */
- (NSUInteger)formDataCount;

/**
 Generate a hydrated `TNLRequest` from the receiver
 @param uploadFormat The format to use for uploading, see `TNLMultipartFormDataUploadFormat`
 @param error If the method returns `nil`, the error will be populated with
 @return a `TNLHTTPRequest` that is hydrated and can be used for a `TNLRequestOperation`'s _hydratedRequest_
 */
- (id<TNLRequest>)generateRequestWithUploadFormat:(TNLXMultipartFormDataUploadFormat)uploadFormat error:(out NSError **)error;

/**
 A convenience delegate for hydrating `TNLMultipartFormDataRequest`s

 The returned `TNLRequestHydrater` will use `[TNLMultipartFormDataRequest generateRequestWithUploadFormat:error:]`
 @param uploadFormat the format to use for uploading, see `TNLMultipartFormDataUploadFormat`
 @return a `TNLRequestHydrater` that can be used by a concrete `TNLRequestDelegate` implementation for any `TNLRequestOperation` backed by a `TNLMultipartFormDataRequest` as its _originalRequest_.
 */
+ (id<TNLRequestHydrater>)multipartFormDataRequestHydraterForUploadFormat:(TNLXMultipartFormDataUploadFormat)uploadFormat;

@end

/**
 An object encapsulating the form data info of a `TNLMultipartFormDataRequest`.
 */
@interface TNLXFormDataEntry : NSObject <NSCopying> // TODO:[nobrien] - <NSCoding>

/**
 Create a `TNLFormDataEntry`
 @param data The data to POST
 @param name The name of the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest`
 */
+ (instancetype)formDataWithData:(NSData *)data name:(NSString *)name;

/**
 Create a `TNLFormDataEntry`
 @param data The data to POST
 @param name The name of the entry
 @param type The content type of the entry.  See `TNLHTTPContentType` constants.
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest`
 */
+ (instancetype)formDataWithData:(NSData *)data name:(NSString *)name type:(NSString *)type fileName:(NSString *)fileName;

/**
 Create a `TNLFormDataEntry`
 @param filePath The path to the file to POST
 @param name The name of the entry
 @param type The content type of the entry.  See `TNLHTTPContentType` constants.
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest`
 */
+ (instancetype)formDataWithFile:(NSString *)filePath name:(NSString *)name type:(NSString *)type fileName:(NSString *)fileName;

// TODO:[nobrien] - support nested multipart/form-data

@property (nonatomic, readonly, copy) NSString *filePath;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *type; // see TNLHTTP.h for TNLHTTPContentType constants
@property (nonatomic, readonly, copy) NSString *fileName;

@end

@interface TNLXFormDataEntry (SpecificFormData)

/**
 Create a `TNLFormDataEntry`
 @param filePath The path to the JPEG image to POST
 @param name The name of the entry
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest` of type `TNLHTTPContentTypeImageJPEG`
 */
+ (instancetype)formDataWithJPEGFile:(NSString *)filePath name:(NSString *)name fileName:(NSString *)fileName;

/**
 Create a `TNLFormDataEntry`
 @param data The JPEG data to POST
 @param name The name of the entry
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest` of type `TNLHTTPContentTypeImageJPEG`
 */
+ (instancetype)formDataWithJPEGData:(NSData *)data name:(NSString *)name fileName:(NSString *)fileName;

/**
 Create a `TNLFormDataEntry`
 @param filePath The path to the Quicktime video to POST
 @param name The name of the entry
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest` of type `TNLHTTPContentTypeVideoQuicktime`
 */
+ (instancetype)formDataWithQuicktimeVideoFile:(NSString *)filePath name:(NSString *)name fileName:(NSString *)fileName;

/**
 Create a `TNLFormDataEntry`
 @param text The text to POST
 @param name The name of the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest` with no `type` nor `fileName`
 */
+ (instancetype)formDataWithText:(NSString *)text name:(NSString *)name;

/**
 Create a `TNLFormDataEntry`
 @param filePath The path to the JSON file to POST
 @param name The name of the entry
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest` of type `TNLHTTPContentTypeJSON`
 */
+ (instancetype)formDataWithJSONFile:(NSString *)filePath name:(NSString *)name fileName:(NSString *)fileName;

/**
 Create a `TNLFormDataEntry`
 @param data The JSON data to POST
 @param name The name of the entry
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest` of type `TNLHTTPContentTypeJSON`
 */
+ (instancetype)formDataWithJSONData:(NSData *)data name:(NSString *)name fileName:(NSString *)fileName;

/**
 Create a `TNLFormDataEntry`
 @param object The JSON object to be serialized and used to POST
 @param name The name of the entry
 @param fileName The file name for the server to use for the entry
 @return A form data entry for use with a `TNLMultipartFormDataRequest` of type `TNLHTTPContentTypeJSON`
 */
+ (instancetype)formDataWithJSONObject:(id)object name:(NSString *)name fileName:(NSString *)fileName;

@end

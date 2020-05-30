//
//  TNLMultipartFormData.m
//  TwitterNetworkLayer
//
//  Created on 8/22/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSDictionary+TNLAdditions.h"
#import "TNLError.h"
#import "TNLHTTP.h"
#import "TNLRequestHydrater.h"
#import "TNLRequestOperation.h"
#import "TNLTemporaryFile.h"
#import "TNLXMultipartFormData.h"

NSString * const TNLXMultipartFormDataErrorDomain = @"TNLXMultipartFormDataErrorDomain";

@interface TNLTemporaryFile : NSObject <TNLTemporaryFile>

- (instancetype)init;
+ (instancetype)temporaryFileWithExistingFilePath:(NSString *)path error:(out NSError **)error;

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly, getter = isOpen) BOOL open;

- (BOOL)consumeExistingFile:(NSString *)path error:(out NSError **)error;
- (BOOL)close:(out NSError **)error;
- (BOOL)open:(out NSError **)error;
- (BOOL)appendData:(NSData *)data error:(out NSError **)error;
- (BOOL)moveToPath:(NSString *)path error:(out NSError **)error;

@end

@interface TNLXMultipartFormDataRequestHydrater : NSObject <TNLRequestHydrater>
@property (nonatomic, readonly) TNLXMultipartFormDataUploadFormat uploadFormat;
- (instancetype)initWithUploadFormat:(TNLXMultipartFormDataUploadFormat)format;
@end

static NSError *TNLXMultipartFormDataErrorCreateWithCode(TNLXMultipartFormDataErrorCode code);
static NSError *TNLXMultipartFormDataErrorCreateWithCodeAndUnderlyingError(TNLXMultipartFormDataErrorCode code, NSError *underlyingError);
static NSError *TNLXMultipartFormDataErrorCreateWithCodeAndUserInfo(TNLXMultipartFormDataErrorCode code, NSDictionary *userInfo);

NS_INLINE BOOL TNLXFormDataEntryAppendData(NSData *data, id dataOrTemporaryFile, NSError ** outError)
{
    if ([dataOrTemporaryFile isKindOfClass:[TNLTemporaryFile class]]) {
        return [(TNLTemporaryFile *)dataOrTemporaryFile appendData:data error:outError];
    } else {
        [(NSMutableData *)dataOrTemporaryFile appendData:data];
        return YES;
    }
}

NS_INLINE BOOL TNLXFormDataEntryAppendString(NSString *string, id dataOrTemporaryFile, NSError ** outError)
{
    return TNLXFormDataEntryAppendData([string dataUsingEncoding:NSUTF8StringEncoding], dataOrTemporaryFile, outError);
}

NS_INLINE BOOL TNLXFormDataEntryAppendFile(NSString *filePath, id dataOrTemporaryFile, NSError ** outError)
{
    NSError *theError = nil;

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!fileHandle) {
        theError = TNLXMultipartFormDataErrorCreateWithCodeAndUnderlyingError(TNLXMultipartFormDataErrorCodeInvalidFormDataEntry, [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil]);
    } else {
        do {
            @autoreleasepool {
                NSData *data = [fileHandle readDataOfLength:UINT16_MAX];
                if (!data.length) {
                    break;
                }
                TNLXFormDataEntryAppendData(data, dataOrTemporaryFile, &theError);
            }
        } while (!theError);
        [fileHandle closeFile];
    }

    return !theError;
}

@interface TNLXMultipartFormDataUploadRequest : NSObject <TNLRequest>
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSDictionary *allHTTPHeaderFields;
- (instancetype)initWithURL:(NSURL *)url boundary:(NSString *)boundary headers:(NSDictionary *)headers;
@end

@interface TNLXMultipartFormDataUploadDataRequest : TNLXMultipartFormDataUploadRequest
@property (nonatomic) NSData *HTTPBody;
@end

@interface TNLXMultipartFormDataUploadFileRequest : TNLXMultipartFormDataUploadRequest
@property (nonatomic) TNLTemporaryFile *temporaryFile;
@property (nonatomic, readonly) NSString *HTTPBodyFilePath;
@end

@interface TNLXFormDataEntry (Protected)
- (BOOL)appendToDataOrTemporaryFile:(id)dataOrTemporaryFile withBoundary:(NSString *)boundary error:(out NSError **)error;
@end

@implementation TNLXMultipartFormDataRequest
{
    NSMutableArray *_formDataObjects;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _formDataObjects = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSString *)boundary
{
    static char sBoundaryCharacters[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    if (!_boundary) {
        _boundary = [NSString stringWithFormat:@"TNLX.multipart.boundary-%c%c%c%c%c%c%c%c%c%c%c%c",
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))],
                     sBoundaryCharacters[arc4random_uniform(sizeof(sBoundaryCharacters))]];
    }
    return _boundary;
}

- (TNLHTTPMethod)HTTPMethodValue
{
    return TNLHTTPMethodPOST;
}

- (void)addFormData:(TNLXFormDataEntry *)formData
{
    [_formDataObjects addObject:formData];
}

- (NSUInteger)formDataCount
{
    return _formDataObjects.count;
}

- (id<TNLRequest>)generateRequestWithUploadFormat:(TNLXMultipartFormDataUploadFormat)uploadFormat error:(out NSError **)error
{
    NSError *theError = nil;
    id<TNLRequest> request = nil;

    NSString *boundary = self.boundary;
    NSCharacterSet *charSet = [[NSCharacterSet characterSetWithCharactersInString:@"01234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ.-_abcdefghijklmnopqrstuvwxyz"] invertedSet];
    if ([boundary rangeOfCharacterFromSet:charSet].length == 0) {

        NSArray *formDataItems = [_formDataObjects copy];
        NSURL *url = self.URL;
        NSDictionary *headers = self.allHTTPHeaderFields;
        NSMutableData *data = nil;
        TNLTemporaryFile *tempFile = nil;
        if (TNLXMultipartFormDataUploadFormatFile == uploadFormat) {
            tempFile = [[TNLTemporaryFile alloc] init];
            [tempFile open:&theError];
        } else {
            data = [[NSMutableData alloc] init];
        }

        if (!theError) {
            for (TNLXFormDataEntry *formDataItem in formDataItems) {
                if (![formDataItem appendToDataOrTemporaryFile:(tempFile ?: data) withBoundary:boundary error:&theError]) {
                    break;
                }
            }
        }

        if (!theError) {
            TNLXFormDataEntryAppendString([NSString stringWithFormat:@"--%@--\r\n", boundary], (tempFile ?: data), &theError);
        }

        [tempFile close:(theError) ? NULL : &theError];

        if (!theError) {
            switch (uploadFormat) {
                case TNLXMultipartFormDataUploadFormatFile:
                    request = [[TNLXMultipartFormDataUploadFileRequest alloc] initWithURL:url boundary:boundary headers:headers];
                    [(TNLXMultipartFormDataUploadFileRequest *)request setTemporaryFile:tempFile];
                    break;
                case TNLXMultipartFormDataUploadFormatData:
                    request = [[TNLXMultipartFormDataUploadDataRequest alloc] initWithURL:url boundary:boundary headers:headers];
                    [(TNLXMultipartFormDataUploadDataRequest *)request setHTTPBody:data];
                    break;
                default:
                    assert(false);
                    break;
            }
        }

    } else {
        theError = TNLXMultipartFormDataErrorCreateWithCodeAndUserInfo(TNLXMultipartFormDataErrorCodeInvalidBoundary, @{ @"boundary" : boundary });
    }

    assert(theError || request);
    if (error) {
        *error = theError;
    }
    return (theError) ? nil : request;
}

- (id)copyWithZone:(NSZone *)zone
{
    TNLXMultipartFormDataRequest *copy = [[TNLXMultipartFormDataRequest alloc] init];
    copy->_formDataObjects = [_formDataObjects mutableCopy];
    copy.boundary = self.boundary;
    copy.URL = self.URL;
    copy.allHTTPHeaderFields = self.allHTTPHeaderFields;
    return copy;
}

+ (id<TNLRequestHydrater>)multipartFormDataRequestHydraterForUploadFormat:(TNLXMultipartFormDataUploadFormat)uploadFormat
{
    return [[TNLXMultipartFormDataRequestHydrater alloc] initWithUploadFormat:uploadFormat];
}

@end

@implementation TNLXFormDataEntry

- (instancetype)initWithFilePath:(NSString *)filePath data:(NSData *)data name:(NSString *)name type:(NSString *)type fileName:(NSString *)fileName
{
    if (self = [super init]) {
        _filePath = [filePath copy];
        _data = data;
        _name = [name copy];
        _type = [type copy];
        _fileName = [fileName copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    TNLXFormDataEntry *formData = [[TNLXFormDataEntry alloc] initWithFilePath:self.filePath data:self.data name:self.name type:self.type fileName:self.fileName];
    return formData;
}

+ (instancetype)formDataWithData:(NSData *)data name:(NSString *)name
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:nil data:data name:name type:nil fileName:nil];
}

+ (instancetype)formDataWithData:(NSData *)data name:(NSString *)name type:(NSString *)type fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:nil data:data name:name type:type fileName:fileName];
}

+ (instancetype)formDataWithFile:(NSString *)filePath name:(NSString *)name type:(NSString *)type fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:filePath data:nil name:name type:type fileName:fileName];
}

@end

@implementation TNLXFormDataEntry (SpecificFormData)

+ (instancetype)formDataWithJPEGFile:(NSString *)filePath name:(NSString *)name fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:filePath data:nil name:name type:TNLHTTPContentTypeJPEGImage fileName:fileName];
}

+ (instancetype)formDataWithJPEGData:(NSData *)data name:(NSString *)name fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:nil data:data name:name type:TNLHTTPContentTypeJPEGImage fileName:fileName];
}

+ (instancetype)formDataWithQuicktimeVideoFile:(NSString *)filePath name:(NSString *)name fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:filePath data:nil name:name type:TNLHTTPContentTypeQuicktimeVideo fileName:fileName];
}

+ (instancetype)formDataWithText:(NSString *)text name:(NSString *)name
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:nil data:[text dataUsingEncoding:NSUTF8StringEncoding] name:name type:nil fileName:nil];
}

+ (instancetype)formDataWithJSONFile:(NSString *)filePath name:(NSString *)name fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:filePath data:nil name:name type:TNLHTTPContentTypeJSON fileName:fileName];
}

+ (instancetype)formDataWithJSONData:(NSData *)data name:(NSString *)name fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:nil data:data name:name type:TNLHTTPContentTypeJSON fileName:fileName];
}

+ (instancetype)formDataWithJSONObject:(id)object name:(NSString *)name fileName:(NSString *)fileName
{
    return [[TNLXFormDataEntry alloc] initWithFilePath:nil data:[NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] name:name type:TNLHTTPContentTypeJSON fileName:fileName];
}

@end

@implementation TNLXFormDataEntry (Protected)

- (BOOL)appendToDataOrTemporaryFile:(id)dataOrTemporaryFile withBoundary:(NSString *)boundary error:(out NSError *__autoreleasing *)error
{
    NSError *theError = nil;

    NSString *name = self.name;
    NSString *contentType = self.type;
    NSString *fileName = self.fileName;

    NSString *filePath = self.filePath;
    NSData *data = self.data;

    if (!name) {
        theError = TNLXMultipartFormDataErrorCreateWithCode(TNLXMultipartFormDataErrorCodeInvalidFormDataEntry);
    } else if (!!contentType ^ !!fileName) {
        theError = TNLXMultipartFormDataErrorCreateWithCode(TNLXMultipartFormDataErrorCodeInvalidFormDataEntry);
    } else if (!(!!filePath ^ !!data)) {
        theError = TNLXMultipartFormDataErrorCreateWithCode(TNLXMultipartFormDataErrorCodeInvalidFormDataEntry);
    }

    if (!theError) {
        TNLXFormDataEntryAppendString(@"--", dataOrTemporaryFile, &theError);
    }
    if (!theError) {
        TNLXFormDataEntryAppendString(boundary, dataOrTemporaryFile, &theError);
    }
    if (!theError) {
        TNLXFormDataEntryAppendString(@"\r\n", dataOrTemporaryFile, &theError);
    }

    if (!theError) {
        TNLXFormDataEntryAppendString(@"Content-Disposition: form-data; name=\"", dataOrTemporaryFile, &theError);
    }
    if (!theError) {
        TNLXFormDataEntryAppendString(name, dataOrTemporaryFile, &theError);
    }
    if (!theError) {
        TNLXFormDataEntryAppendString(@"\"", dataOrTemporaryFile, &theError);
    }
    if (contentType) {
        if (!theError) {
            TNLXFormDataEntryAppendString(@"; filename=\"", dataOrTemporaryFile, &theError);
        }
        if (!theError) {
            assert(fileName);
            TNLXFormDataEntryAppendString(fileName, dataOrTemporaryFile, &theError);
        }
        if (!theError) {
            TNLXFormDataEntryAppendString(@"\"\r\nContent-Type: ", dataOrTemporaryFile, &theError);
        }
        if (!theError) {
            TNLXFormDataEntryAppendString(contentType, dataOrTemporaryFile, &theError);
        }
    }
    if (!theError) {
        TNLXFormDataEntryAppendString(@"\r\n\r\n", dataOrTemporaryFile, &theError);
    }

    if (filePath) {
        if (!theError) {
            TNLXFormDataEntryAppendFile(filePath, dataOrTemporaryFile, &theError);
        }
    } else {
        if (!theError) {
            assert(data);
            TNLXFormDataEntryAppendData(data, dataOrTemporaryFile, &theError);
        }
    }

    if (!theError) {
        TNLXFormDataEntryAppendString(@"\r\n", dataOrTemporaryFile, &theError);
    }

    if (error) {
        *error = theError;
    }
    return !theError;
}

@end

@implementation TNLXMultipartFormDataUploadRequest

- (instancetype)initWithURL:(NSURL *)url boundary:(NSString *)boundary headers:(NSDictionary *)headers
{
    if (self = [super init]) {
        _URL = url;
        NSMutableDictionary *mHeaders = [headers mutableCopy] ?: [NSMutableDictionary dictionary];
        [mHeaders tnl_setObject:[NSString stringWithFormat:@"%@; boundary=%@", TNLHTTPContentTypeMultipartFormData, boundary] forCaseInsensitiveKey:@"Content-Type"];
        _allHTTPHeaderFields = [mHeaders copy];
    }
    return self;
}

- (TNLHTTPMethod)HTTPMethodValue
{
    return TNLHTTPMethodPOST;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

@implementation TNLXMultipartFormDataUploadDataRequest
@end

@implementation TNLXMultipartFormDataUploadFileRequest

- (void)setTemporaryFile:(TNLTemporaryFile *)temporaryFile
{
    if (temporaryFile != _temporaryFile) {
        _temporaryFile = temporaryFile;
        _HTTPBodyFilePath = temporaryFile.path;
    }
}

@end

@implementation TNLXMultipartFormDataRequestHydrater

- (instancetype)init
{
    return [self initWithUploadFormat:TNLXMultipartFormDataUploadFormatDefault];
}

- (instancetype)initWithUploadFormat:(TNLXMultipartFormDataUploadFormat)format
{
    if (self = [super init]) {
        _uploadFormat = format;
    }
    return self;
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op hydrateRequest:(id<TNLRequest>)request completion:(TNLRequestHydrateCompletionBlock)complete
{
    NSError *error;
    if ([request isKindOfClass:[TNLXMultipartFormDataRequest class]]) {
        request = [(TNLXMultipartFormDataRequest *)request generateRequestWithUploadFormat:self.uploadFormat error:&error];
    }
    complete(request, error);
}

@end

static NSError *TNLXMultipartFormDataErrorCreateWithCode(TNLXMultipartFormDataErrorCode code)
{
    return TNLXMultipartFormDataErrorCreateWithCodeAndUserInfo(code, nil);
}

static NSError *TNLXMultipartFormDataErrorCreateWithCodeAndUnderlyingError(TNLXMultipartFormDataErrorCode code, NSError *underlyingError)
{
    assert(underlyingError);
    return TNLXMultipartFormDataErrorCreateWithCodeAndUserInfo(code, @{ NSUnderlyingErrorKey : underlyingError });
}

static NSError *TNLXMultipartFormDataErrorCreateWithCodeAndUserInfo(TNLXMultipartFormDataErrorCode code, NSDictionary *userInfo)
{
    return [NSError errorWithDomain:TNLErrorDomain code:code userInfo:userInfo];
}

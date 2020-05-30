//
//  TAPIUploadMediaRequest.m
//  TNLExample
//
//  Created on 5/30/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TAPIUploadMediaRequest.h"
#import "TNLXMultipartFormData.h"

@implementation TAPIUploadMediaRequest
{
    id<TNLRequest> _underlyingRequest;
}

+ (Class)responseClass
{
    return [TAPIUploadMediaResponse class];
}

- (instancetype)initWithImageData:(NSData *)imageData
{
    if (self = [super init]) {
        TNLXMultipartFormDataRequest *request = [[TNLXMultipartFormDataRequest alloc] init];
        request.URL = self.URL;
        [request addFormData:[TNLXFormDataEntry formDataWithText:@"phone" name:@"adc"]];
        [request addFormData:[TNLXFormDataEntry formDataWithJPEGData:imageData name:@"media" fileName:@"./image.jpg"]];
        _underlyingRequest = [request generateRequestWithUploadFormat:TNLXMultipartFormDataUploadFormatFile error:NULL];
    }
    return self;
}

- (TNLHTTPMethod)HTTPMethodValue
{
    return TNLHTTPMethodPOST;
}

- (NSString *)domain
{
    return @"upload.twitter.com";
}

- (NSString *)endpoint
{
    return @"media/upload.json";
}

- (NSString *)HTTPBodyFilePath
{
    return _underlyingRequest.HTTPBodyFilePath;
}

- (NSDictionary *)allHTTPHeaderFields
{
    NSMutableDictionary *fields = [[super allHTTPHeaderFields] mutableCopy] ?: [[NSMutableDictionary alloc] init];
    [fields addEntriesFromDictionary:_underlyingRequest.allHTTPHeaderFields];
    return fields;
}

@end

@implementation TAPIUploadMediaResponse

@synthesize didSucceed = _didSucceed;

- (void)prepare
{
    [super prepare];
    _didSucceed = (200 == _info.statusCode);
}

@end

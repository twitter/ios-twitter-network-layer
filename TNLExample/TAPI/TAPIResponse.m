//
//  TAPIResponse.m
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TAPIError.h"
#import "TAPIResponse.h"
#import "TNL_Project.h"

NS_INLINE BOOL _DataBeginsWithHTMLDocType(NSData *data)
{
    static const char sDocType[] = "<!DOCTYPE html";
    static const size_t sDocTypeLength = (sizeof(sDocType) / sizeof(sDocType[0])) - 1; // minus 1 to ignore the NULL terminator
    return data.length >= sDocTypeLength && 0 == strncmp(data.bytes, sDocType, sDocTypeLength);
}

static id _ParseAPIResponse(TNLResponseInfo *info, NSError ** parseErrorOut, NSError ** apiErrorOut);
static NSArray *_ExtractAPIErrors(id parsedObject);

@implementation TAPIResponse

@synthesize apiError = _apiError;
@synthesize parseError = _parseError;
@synthesize parsedObject = _parsedObject;

- (void)prepare
{
    [super prepare];
    if (!_operationError) {
        NSError *apiError;
        NSError *parseError;
        _parsedObject = _ParseAPIResponse(_info, &parseError, &apiError);
        _parseError = parseError;
        _apiError = apiError;

        TNLAttemptMetrics *metrics = _metrics.attemptMetrics.lastObject;
        metrics.responseBodyParseError = parseError;
        if (apiError) {
            metrics.APIErrors = @[apiError];
        }
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _parsedObject = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSString class], [NSNumber class], [NSArray class], [NSDictionary class], nil]
                                              forKey:@"parsedObject"];
        _parseError = [coder decodeObjectOfClass:[NSError class] forKey:@"parseError"];
        _apiError = [coder decodeObjectOfClass:[NSError class] forKey:@"apiError"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:TNLErrorToSecureCodingError(_parsedObject) forKey:@"parsedObject"];
    [aCoder encodeObject:TNLErrorToSecureCodingError(_apiError) forKey:@"apiError"];
    [aCoder encodeObject:TNLErrorToSecureCodingError(_parseError) forKey:@"parseError"];
}

- (NSError *)anyError
{
    return self.operationError ?: self.parseError ?: self.apiError;
}

@end

static id _ParseAPIResponse(TNLResponseInfo *info, NSError ** errorOut, NSError ** apiErrorOut)
{
    id json = nil;
    NSError *parseError = nil;
    __block NSError *apiError = TNLHTTPStatusCodeIsSuccess(info.statusCode) ? nil : [NSError errorWithDomain:TAPIErrorDomain code:0 userInfo:nil];

    NSInteger statusCode = info.statusCode;
    NSData *data = info.data;
    TNLAssert(statusCode > 0);

    BOOL hasDocTypePrefix = _DataBeginsWithHTMLDocType(data);
    if (hasDocTypePrefix) {
        parseError = [NSError errorWithDomain:TAPIOperationErrorDomain
                                         code:TAPIOperationErrorCodeServiceEncounteredTechnicalError
                                     userInfo:nil];
    } else {
        json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (json) {
            NSArray *apiErrors = _ExtractAPIErrors(json);

            // Underlying behavior in some 4XX errors
            if (TNLHTTPStatusCodeIsClientError(statusCode)) {
                [apiErrors enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    NSError *currentError = obj;
                    if ([currentError.domain isEqualToString:TAPIErrorDomain]) {
                        apiError = currentError;
                        *stop = YES;
                    }
                }];
            }
        } else {
            parseError = [NSError errorWithDomain:TAPIParseErrorDomain
                                             code:TAPIParseErrorCodeCannotParseResponse
                                         userInfo:(parseError) ? @{ NSUnderlyingErrorKey : parseError } : nil];
        }
    }

    if (errorOut) {
        *errorOut = parseError;
    }
    if (apiErrorOut) {
        *apiErrorOut = apiError;
    }
    return json;
}

static NSArray *_ExtractAPIErrors(id parsedObject)
{
    TNLAssert(parsedObject != nil);
    NSMutableArray *errorItems = [[NSMutableArray alloc] init];
    if ([parsedObject isKindOfClass:[NSDictionary class]]) {
        id errors = [parsedObject objectForKey:@"errors"];
        if ([errors isKindOfClass:[NSArray class]]) {
            [errors enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                BOOL successfullyParsedError = NO;
                if ([obj isKindOfClass:[NSDictionary class]]) {
                    id codeObject = [obj objectForKey:@"code"];
                    id messageObject = [obj objectForKey:@"message"];

                    if (codeObject && messageObject) {
                        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                        if (messageObject) {
                            userInfo[NSLocalizedDescriptionKey] = messageObject;
                        }
                        NSInteger code = [codeObject integerValue];
                        id timestamp = [obj objectForKey:@"timestamp"];
                        if (timestamp) {
                            userInfo[@"timestamp"] = timestamp;
                        }
                        [errorItems addObject:[NSError errorWithDomain:TAPIErrorDomain
                                                                  code:code
                                                              userInfo:userInfo]];
                        successfullyParsedError = YES;
                    }
                }

                if (!successfullyParsedError) {
                    NSLog(@"Failed to parse server error:[%@]", obj);
                }
            }];
        }
    }
    return errorItems;
}

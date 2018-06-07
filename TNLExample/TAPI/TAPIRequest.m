//
//  TAPIRequest.m
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TAPIRequest.h"
#import "TNL_Project.h"

NSString * const TAPIRequestDomainDefault = @"api.twitter.com";
NSString * const TAPIRequestVersion1_1 = @"1.1";

@interface TAPIRetryPolicyProvider : NSObject <TNLRequestRetryPolicyProvider>
@end

@implementation TAPIRequest
{
    NSString *_baseURLString;
    TNLParameterCollection *_parameters;
}

- (NSString *)scheme
{
    return @"https";
}

- (NSString *)domain
{
    return TAPIRequestDomainDefault;
}

- (NSString *)version
{
    return TAPIRequestVersionDefault;
}

- (NSString *)endpoint
{
    // Requires override
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (TNLParameterCollection *)parameters
{
    if (!_parameters) {
        TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] init];
        [self prepareParameters:params];
        _parameters = [params copy];
    }
    return _parameters;
}

- (void)prepareParameters:(TNLMutableParameterCollection *)params
{
}

- (TNLHTTPMethod)HTTPMethodValue
{
    return TNLHTTPMethodGET;
}

- (NSDictionary *)allHTTPHeaderFields
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"Accept"] = TNLHTTPContentTypeJSON;

    if (self.HTTPMethodValue == TNLHTTPMethodPOST) {
        d[@"Content-Type"] = TNLHTTPContentTypeURLEncodedString;
    }

    return d;
}

+ (Class)responseClass
{
    return Nil;
}

- (NSString *)baseURLString
{
    if (_baseURLString) {
        return _baseURLString;
    }

    NSMutableString *URLString = [NSMutableString string];
    NSString *component;

    component = self.scheme;
    if (0 == component.length) {
        return nil;
    }
    [URLString appendString:component];
    [URLString appendString:@"://"];

    component = self.domain;
    if (0 == component.length) {
        return nil;
    }
    [URLString appendString:component];

    component = self.version;
    if (0 != component.length) {
        [URLString appendString:@"/"];
        [URLString appendString:component];
    }

    component = self.endpoint;
    if (0 == component.length) {
        return nil;
    }
    [URLString appendString:@"/"];
    [URLString appendString:component];

    _baseURLString = [URLString copy];
    return _baseURLString;
}

- (NSURL *)URL
{
    NSMutableString *URLString = (id)[self.baseURLString mutableCopy];
    if (!URLString) {
        return nil;
    }

    TNLParameterCollection *parameters = self.parameters;
    if (parameters.count > 0 && TNLHTTPMethodPOST != self.HTTPMethodValue) {
        NSString *component = [parameters stableURLEncodedStringValue];
        if (0 != component.length) {
            [URLString appendString:@"?"];
            [URLString appendString:component];
        }
    }

    return [NSURL URLWithString:URLString];
}

- (NSData *)HTTPBody
{
    NSData *body = nil;
    if (TNLHTTPMethodPOST == self.HTTPMethodValue) {
        @autoreleasepool {
            TNLParameterCollection *parameters = self.parameters;
            if (parameters.count > 0) {
                NSString *URLParameters = [parameters stableURLEncodedStringValue];
                if (URLParameters.length > 0) {
                    body = [URLParameters dataUsingEncoding:NSUTF8StringEncoding];
                }
            }
        }
    }
    return body;
}

+ (TNLRequestConfiguration *)configuration
{
    static TNLRequestConfiguration *sDefaultConfig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
        config.URLCache = nil;
        config.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.redirectPolicy = TNLRequestRedirectPolicyRedirectToSameHost;
        sDefaultConfig = [config copy];
    });
    return sDefaultConfig;
}

+ (id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
{
    return nil;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

@implementation TAPIRetriableRequest

+ (id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
{
    static TAPIRetryPolicyProvider *sActionRetryPolicyProvider;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sActionRetryPolicyProvider = [[TAPIRetryPolicyProvider alloc] init];
    });
    return sActionRetryPolicyProvider;
}

@end

@implementation TAPIRetryPolicyProvider
{
    TNLRequestRetryPolicyConfiguration *_config;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _config = [[TNLRequestRetryPolicyConfiguration alloc] initWithRetriableMethods:@[@"POST"]
                                                                           statusCodes:@[@503]
                                                                         URLErrorCodes:TNLStandardRetriableURLErrorCodes()
                                                                       POSIXErrorCodes:TNLStandardRetriablePOSIXErrorCodes()];
    }
    return self;
}

- (BOOL)tnl_shouldRetryRequestOperation:(TNLRequestOperation *)op withResponse:(TNLResponse *)response
{
    // one retry
    if (response.metrics.attemptCount != 0) {
        return NO;
    }

    return [_config requestCanBeRetriedForResponse:response];
}

- (NSTimeInterval)tnl_delayBeforeRetryForRequestOperation:(TNLRequestOperation *)op withResponse:(TNLResponse *)response
{
    return 1.0;
}

@end

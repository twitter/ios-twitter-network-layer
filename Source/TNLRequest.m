//
//  TNLRequest.m
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright © 2020 Twitter, Inc. All rights reserved.
//

#import "NSDictionary+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLError.h"
#import "TNLRequest.h"
#import "TNLRequestConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

static NSUInteger const kMaxBytesToCompare = 1024;

#pragma mark - TNLRequest Utilities

BOOL TNLRequestValidate(id<TNLRequest> __nullable request,
                        TNLRequestConfiguration * __nullable config,
                        NSError * __nullable * __nullable errorOut)
{
    NSError *error = nil;
    NSURL *url = [request respondsToSelector:@selector(URL)] ? request.URL : nil;
    if (!url) {
        error = TNLErrorCreateWithCode(TNLErrorCodeRequestInvalid);
    } else if (!url.host || !url.scheme || url.isFileReferenceURL) {
        error = TNLErrorCreateWithCode(TNLErrorCodeRequestInvalidURL);
    } else {
        TNLHTTPMethod method = TNLRequestGetHTTPMethodValue(request);
        if (TNLHTTPMethodUnknown == method) {
            error = TNLErrorCreateWithCode(TNLErrorCodeRequestInvalidHTTPMethod);
        } else {
            const BOOL isDownload = (TNLResponseDataConsumptionModeSaveToDisk == config.responseDataConsumptionMode);
            const BOOL isBackground = (TNLRequestExecutionModeBackground == config.executionMode);
            union {
                struct {
                    BOOL data:1;
                    BOOL file:1;
                    BOOL stream:1;
                    char padding:5;
                } body;
                char hasBody;
            } bodyUnion;

            bodyUnion.hasBody = 0;
            bodyUnion.body.data = [request respondsToSelector:@selector(HTTPBody)] && nil != request.HTTPBody;
            bodyUnion.body.file = [request respondsToSelector:@selector(HTTPBodyFilePath)] && nil != request.HTTPBodyFilePath;
            bodyUnion.body.stream = [request respondsToSelector:@selector(HTTPBodyStream)] && nil != request.HTTPBodyStream;

            if (isBackground) {
                if (!isDownload) {
                    if (!bodyUnion.body.file && !bodyUnion.body.data) {
                        // upload must have a file or data for the body.
                        // nil and stream are invalid in the background
                        error = TNLErrorCreateWithCode(TNLErrorCodeRequestInvalidBackgroundRequest);
                    }
                }
            }

            if (isDownload && bodyUnion.hasBody) {
                error = TNLErrorCreateWithCode(TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
            }
        }
    }

    if (errorOut) {
        *errorOut = error;
    }

    return !error;
}

NSURLRequest * __nullable TNLRequestToNSURLRequest(id<TNLRequest> __nullable request,
                                                   TNLRequestConfiguration * __nullable config,
                                                   NSError * __nullable * __nullable errorOut)
{
    NSURLRequest *URLRequest;
    if ([request isKindOfClass:[NSURLRequest class]] && !config) {
        URLRequest = (NSURLRequest *)request;
    } else {
        URLRequest = TNLRequestToNSMutableURLRequest(request, config, errorOut);
    }
    return [URLRequest copy];
}

NSMutableURLRequest * __nullable TNLRequestToNSMutableURLRequest(id<TNLRequest> __nullable request,
                                                                 TNLRequestConfiguration * __nullable config,
                                                                 NSError * __nullable * __nullable errorOut)
{
    if (![request respondsToSelector:@selector(URL)]) {
        if (errorOut) {
            *errorOut = TNLErrorCreateWithCode(TNLErrorCodeRequestInvalidURL);
        }
        return nil;
    }

    NSMutableURLRequest *urlRequest = nil;

    NSURL *URL = request.URL;
    urlRequest = (URL) ? [[NSMutableURLRequest alloc] initWithURL:URL] : [[NSMutableURLRequest alloc] init];
    urlRequest.HTTPMethod = TNLRequestGetHTTPMethod(request);

    if ([request respondsToSelector:@selector(HTTPBody)] && [request HTTPBody]) {
        urlRequest.HTTPBody = [request HTTPBody];
    } else if ([request respondsToSelector:@selector(HTTPBodyFilePath)] && [request HTTPBodyFilePath]) {
        urlRequest.HTTPBodyStream = [NSInputStream inputStreamWithFileAtPath:[request HTTPBodyFilePath]];
    } else if ([request respondsToSelector:@selector(HTTPBodyStream)] && [request HTTPBodyStream]) {
        urlRequest.HTTPBodyStream = [request HTTPBodyStream];
    }

    if ([request respondsToSelector:@selector(allHTTPHeaderFields)]) {
        urlRequest.allHTTPHeaderFields = [request allHTTPHeaderFields];
    }

    if (config) {
        urlRequest.cachePolicy = config.cachePolicy;
        urlRequest.allowsCellularAccess = config.allowsCellularAccess;
        urlRequest.networkServiceType = config.networkServiceType;
        urlRequest.HTTPShouldHandleCookies = config.shouldSetCookies;
        // urlRequest.HTTPShouldUsePipelining -- move to HTTP/2 instead of worrying about pipelining
        // urlRequest.timeoutInterval -- TNL controls timeout intervals
    }

    return urlRequest;
}

NSString *TNLRequestGetHTTPMethod(id<TNLRequest> __nullable request)
{
    NSString *method = nil;
    if ([request respondsToSelector:@selector(HTTPMethod)]) {
        method = [request HTTPMethod];
    } else if ([request respondsToSelector:@selector(HTTPMethodValue)]) {
        method = TNLHTTPMethodToString([request HTTPMethodValue]);
    }
    return method ?: TNLHTTPMethodToString(TNLHTTPMethodGET);
}

TNLHTTPMethod TNLRequestGetHTTPMethodValue(id<TNLRequest> __nullable request)
{
    TNLHTTPMethod method = TNLHTTPMethodGET;
    if ([request respondsToSelector:@selector(HTTPMethod)]) {
        method = TNLHTTPMethodFromString(request.HTTPMethod);
    } else if ([request respondsToSelector:@selector(HTTPMethodValue)]) {
        method = request.HTTPMethodValue;
    }
    return method;
}

BOOL TNLRequestHasBody(id<TNLRequest> __nullable request)
{
    if ([request respondsToSelector:@selector(HTTPBody)] && request.HTTPBody != nil) {
        return YES;
    }
    if ([request respondsToSelector:@selector(HTTPBodyFilePath)] && request.HTTPBodyFilePath != nil) {
        return YES;
    }
    if ([request respondsToSelector:@selector(HTTPBodyStream)] && request.HTTPBodyStream != nil) {
        return YES;
    }
    return NO;
}

BOOL TNLRequestEqualToRequest(id<TNLRequest> __nullable request1,
                              id<TNLRequest> __nullable request2,
                              BOOL quickBodyCheck)
{
    if (request1 == request2) {
        return YES;
    }

    if (![request1 respondsToSelector:@selector(URL)] || ![request2 respondsToSelector:@selector(URL)]) {
        return NO;
    }

    TNLHTTPMethod method = TNLRequestGetHTTPMethodValue(request1);
    if (TNLRequestGetHTTPMethodValue(request2) != method) {
        return NO;
    }

    if (![request1.URL isEqual:request2.URL]) {
        return NO;
    }

    NSDictionary *headers1 = [request1 respondsToSelector:@selector(allHTTPHeaderFields)] ? [request1 allHTTPHeaderFields] : nil;
    NSDictionary *headers2 = [request2 respondsToSelector:@selector(allHTTPHeaderFields)] ? [request2 allHTTPHeaderFields] : nil;
    if (headers1 != headers2) {
        if (headers1.count != headers2.count) {
            return NO;
        }

        NSDictionary *lowerCaseHeaders1 = [headers1 tnl_mutableCopyWithLowercaseKeys] ?: @{};
        NSDictionary *lowerCaseHeaders2 = [headers2 tnl_mutableCopyWithLowercaseKeys] ?: @{};
        if (![lowerCaseHeaders1 isEqualToDictionary:lowerCaseHeaders2]) {
            return NO;
        }
    }

    if (quickBodyCheck) {
        return TNLRequestHasBody(request1) == TNLRequestHasBody(request2);
    }

    NSData *data1 = [request1 respondsToSelector:@selector(HTTPBody)] ? [request1 HTTPBody] : nil;
    NSData *data2 = [request2 respondsToSelector:@selector(HTTPBody)] ? [request2 HTTPBody] : nil;

    if (data1 != data2) {
        // Compare Data

        if (data1.length != data2.length) {
            return NO;
        } else if (!data1 || !data2) {
            return NO;
        } else if (data1.length > kMaxBytesToCompare) {
            // If the body is too large, don't bother comparing as it would be too expensive
            return NO;
        } else if (![data1 isEqualToData:data2]) {
            return NO;
        }
    } else {
        if (!data1 /* both are nil */) {
            NSString *file1 = [request1 respondsToSelector:@selector(HTTPBodyFilePath)] ? [request1 HTTPBodyFilePath] : nil;
            NSString *file2 = [request2 respondsToSelector:@selector(HTTPBodyFilePath)] ? [request2 HTTPBodyFilePath] : nil;

            if (!file1 && !file2) {
                // Compare streams

                NSInputStream *input1 = [request1 respondsToSelector:@selector(HTTPBodyStream)] ? [request1 HTTPBodyStream] : nil;
                NSInputStream *input2 = [request2 respondsToSelector:@selector(HTTPBodyStream)] ? [request2 HTTPBodyStream] : nil;

                if (input1 != input2) {
                    return NO;
                }
            } else {
                // Compare files

                if (!file1 || !file2 || ![file1 isEqualToString:file2]) {
                    return NO;
                }
            }
        }
    }

    return YES;
}

NS_ASSUME_NONNULL_END

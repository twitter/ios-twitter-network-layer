//
//  TNLRequestRetryPolicyTest.m
//  TwitterNetworkLayerTests
//
//  Created on 8/24/18.
//  Copyright © 2018 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLXContentEncoding.h"

@import TwitterNetworkLayer;
@import XCTest;

@interface BrokenContentEncoder : NSObject <TNLContentEncoder>
@end

@interface TestRetryPolicy : NSObject <TNLConfiguringRetryPolicyProvider>
@end

@interface TNLRequestRetryPolicyTest : XCTestCase
@end

@implementation TNLRequestRetryPolicyTest

- (void)testRetryPolicy
{
    NSURL *URL = [NSURL URLWithString:@"https://fake.domain.com/post/results"];
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.contentEncoder = [[BrokenContentEncoder alloc] init];
    config.retryPolicyProvider = [[TestRetryPolicy alloc] initWithConfiguration:[TNLRequestRetryPolicyConfiguration standardConfiguration]];
    config.protocolOptions = TNLRequestProtocolOptionPseudo;

    NSHTTPURLResponse *URLResponse = [[NSHTTPURLResponse alloc] initWithURL:URL
                                                                 statusCode:200
                                                                HTTPVersion:@"1.1"
                                                               headerFields:nil];
    NSData *URLResponseBody = [@"{\"success\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    [TNLPseudoURLProtocol registerURLResponse:URLResponse
                                         body:URLResponseBody
                                 withEndpoint:URL];
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    __block TNLResponse *response = nil;
    NSDictionary *results = @{
                              @"player1" : @{
                                      @"name" : @"Montoya",
                                      @"score" : @5,
                                      },
                              @"player2" : @{
                                      @"name" : @"Roberts",
                                      @"score" : @6,
                                      }
                              };
    NSData *requestBody = [NSJSONSerialization dataWithJSONObject:results
                                                          options:NSJSONWritingPrettyPrinted
                                                            error:NULL];
    TNLMutableHTTPRequest *request = [TNLMutableHTTPRequest POSTRequestWithURL:URL
                                                              HTTPHeaderFields:nil
                                                                      HTTPBody:requestBody];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                          configuration:config
                                                             completion:^(TNLRequestOperation * _Nonnull operation, TNLResponse * _Nonnull opResponse) {
                                                                 response = opResponse;
                                                             }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertNotNil(response);
    XCTAssertEqual((int)response.info.statusCode, 200);
    XCTAssertNil(response.operationError);
    XCTAssertEqual((int)response.metrics.attemptCount, 2);

    do {
        TNLAttemptMetrics *firstAttemptMetrics = response.metrics.attemptMetrics.firstObject;
        XCTAssertNotNil(firstAttemptMetrics);
        XCTAssertNotNil(firstAttemptMetrics.operationError);
        XCTAssertEqualObjects(firstAttemptMetrics.operationError.domain, TNLErrorDomain);
        XCTAssertEqual(firstAttemptMetrics.operationError.code, TNLErrorCodeRequestOperationRequestContentEncodingFailed);
    } while (0);

    do {
        NSData *requestBodyBase64 = [requestBody base64EncodedDataWithOptions:(NSDataBase64Encoding64CharacterLineLength |
                                                                               NSDataBase64EncodingEndLineWithCarriageReturn |
                                                                               NSDataBase64EncodingEndLineWithLineFeed)];
        TNLAttemptMetrics *lastAttemptMetrics = response.metrics.attemptMetrics.lastObject;
        XCTAssertNotNil(lastAttemptMetrics);
        XCTAssertNil(lastAttemptMetrics.operationError);
        XCTAssertEqualObjects([lastAttemptMetrics.URLRequest valueForHTTPHeaderField:@"Content-Encoding"], @"base64");
        XCTAssertEqualObjects(lastAttemptMetrics.URLRequest.HTTPBody, requestBodyBase64);
    } while (0);
}

@end

@implementation BrokenContentEncoder

- (NSString *)tnl_contentEncodingType
{
    return @"gzip";
}

- (nullable NSData *)tnl_encodeHTTPBody:(NSData *)bodyData
                                  error:(out NSError * __nullable * __nullable)error
{
    if (error) {
        *error = [NSError errorWithDomain:@"broken.encoder"
                                     code:-2
                                 userInfo:nil];
    }
    return nil;
}

@end

@implementation TestRetryPolicy
{
    TNLRequestRetryPolicyConfiguration *_config;
}

- (instancetype)initWithConfiguration:(nullable TNLRequestRetryPolicyConfiguration *)config
{
    if (self = [super init]) {
        _config = [config copy];
    }
    return self;
}

- (nullable TNLRequestRetryPolicyConfiguration *)configuration
{
    return _config;
}

- (BOOL)tnl_shouldRetryRequestOperation:(TNLRequestOperation *)op
                           withResponse:(TNLResponse *)response
{
    if ([response.operationError.domain isEqualToString:TNLErrorDomain] && response.operationError.code == TNLErrorCodeRequestOperationRequestContentEncodingFailed) {
        if (response.metrics.attemptCount > 3) {
            return NO;
        }
        return YES;
    }

    return [_config requestCanBeRetriedForResponse:response];
}

- (NSTimeInterval)tnl_delayBeforeRetryForRequestOperation:(TNLRequestOperation *)op
                                             withResponse:(TNLResponse *)response
{
    return 0.5;
}

- (nullable TNLRequestConfiguration *)tnl_configurationOfRetryForRequestOperation:(TNLRequestOperation *)op
                                                                     withResponse:(TNLResponse *)response
                                                               priorConfiguration:(TNLRequestConfiguration *)priorConfig
{
    if (![response.operationError.domain isEqualToString:TNLErrorDomain]) {
        return nil;
    }

    if (response.operationError.code != TNLErrorCodeRequestOperationRequestContentEncodingFailed) {
        return nil;
    }

    TNLMutableRequestConfiguration *config = [priorConfig mutableCopy];
    if ([priorConfig.contentEncoder.tnl_contentEncodingType isEqualToString:@"base64"]) {
        config.contentEncoder = nil;
    } else {
        config.contentEncoder = [TNLXContentEncoding Base64ContentEncoder];
    }

    return config;
}

- (nullable NSString *)tnl_retryPolicyIdentifier
{
    return @"test.tnl.retry.policy.1";
}

@end

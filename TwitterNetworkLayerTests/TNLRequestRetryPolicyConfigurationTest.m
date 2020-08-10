//
//  TNLRequestRetryPolicyConfigurationTest.m
//  TwitterNetworkLayer
//
//  Created on 11/14/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLHTTPRequest.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLRequestOperation.h"
#import "TNLRequestOperation_Project.h"
#import "TNLRequestRetryPolicyConfiguration.h"

@import XCTest;

@interface TNLRequestRetryPolicyConfigurationTest : XCTestCase
@end

@interface TNLTestRetryPolicyConfigurationRequestOperation : TNLRequestOperation
- (void)setStatusCodeOverride:(TNLHTTPStatusCode)statusCode;
- (void)setMethodOverride:(TNLHTTPMethod)methodOverride;
@end

@implementation TNLRequestRetryPolicyConfigurationTest

- (void)testRetryPolicyConfiguration
{
    TNLMutableRequestRetryPolicyConfiguration *testConfig = [[TNLMutableRequestRetryPolicyConfiguration defaultConfiguration] mutableCopy];
    TNLTestRetryPolicyConfigurationRequestOperation *testRequest = [[TNLTestRetryPolicyConfigurationRequestOperation alloc] initWithRequest:[[TNLMutableHTTPRequest alloc] initWithURL:[NSURL URLWithString:@"http://www.dummy.com"]] responseClass:Nil configuration:nil delegate:nil];

    // GET, 503, no URL errors
    testRequest.statusCodeOverride = TNLHTTPStatusCodeAccepted; // 200
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeEnhanceYourCalm; // 420
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeServiceUnavailable; // 503
    XCTAssertTrue([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.methodOverride = TNLHTTPMethodPOST;
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.methodOverride = TNLHTTPMethodDELETE;
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.methodOverride = TNLHTTPMethodGET;
    testRequest.statusCodeOverride = TNLHTTPStatusCodeBadGateway; // 502
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeNotImplemented; // 501
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeInternalServerError; // 500
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = 0;
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);

    [testConfig setMethodsThatCanBeRetried:@[@"GET", @"POST"]];
    [testConfig setStatusCodesThatCanBeRetried:@[@500, @502, @503]];

    // GET & POST, 500 & 502 & 503
    testRequest.statusCodeOverride = TNLHTTPStatusCodeAccepted; // 200
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeEnhanceYourCalm; // 420
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeServiceUnavailable; // 503
    XCTAssertTrue([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.methodOverride = TNLHTTPMethodPOST;
    XCTAssertTrue([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.methodOverride = TNLHTTPMethodDELETE;
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.methodOverride = TNLHTTPMethodGET;
    testRequest.statusCodeOverride = TNLHTTPStatusCodeBadGateway; // 502
    XCTAssertTrue([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeNotImplemented; // 501
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = TNLHTTPStatusCodeInternalServerError; // 500
    XCTAssertTrue([testConfig requestCanBeRetriedForResponse:testRequest.response]);
    testRequest.statusCodeOverride = 0;
    XCTAssertFalse([testConfig requestCanBeRetriedForResponse:testRequest.response]);
}

@end

@implementation TNLTestRetryPolicyConfigurationRequestOperation
{
    TNLMutableHTTPRequest *_overrideRequest;
    TNLHTTPStatusCode _overrideStatusCode;
}

- (instancetype)initWithRequest:(id<TNLRequest>)request responseClass:(nullable Class)responseClass configuration:(nullable TNLRequestConfiguration *)config delegate:(nullable id<TNLRequestDelegate>)delegate
{
    if (self = [super initWithRequest:request responseClass:Nil configuration:config delegate:delegate]) {
        _overrideRequest = [TNLMutableHTTPRequest HTTPRequestWithRequest:request];
    }
    return self;
}

- (BOOL)isFinished
{
    return YES;
}

- (id<TNLRequest>)originalRequest
{
    return _overrideRequest;
}

- (id<TNLRequest>)hydratedRequest
{
    return _overrideRequest;
}

- (void)setStatusCodeOverride:(TNLHTTPStatusCode)statusCode
{
    _overrideStatusCode = statusCode;
}

- (void)setMethodOverride:(TNLHTTPMethod)methodOverride
{
    _overrideRequest.HTTPMethodValue = methodOverride;
}

- (TNLResponse *)response
{
    // generate a fake response
    NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:self.hydratedRequest.URL statusCode:_overrideStatusCode HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    TNLResponseInfo *info = [[TNLResponseInfo alloc] initWithFinalURLRequest:TNLRequestToNSURLRequest(self.hydratedRequest, nil /*config*/, NULL /*error*/) URLResponse:httpResponse source:TNLResponseSourceNetworkRequest data:[NSData data] temporarySavedFile:nil];
    TNLResponse *response = [self.responseClass responseWithRequest:self.hydratedRequest operationError:nil info:info metrics:[[TNLResponseMetrics alloc] init]];
    return response;
}

@end

//
//  TNLPseudoRequestOperationTest.m
//  TwitterNetworkLayer
//
//  Created on 10/29/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSDictionary+TNLAdditions.h"
#import "TNLError.h"
#import "TNLHTTPRequest.h"
#import "TNLPseudoURLProtocol.h"
#import "TNLRequestDelegate.h"
#import "TNLRequestOperationCancelSource.h"
#import "TNLRequestOperationQueue.h"
#import "TNLRequestRetryPolicyProvider.h"
#import "TNLResponse.h"

@import XCTest;

#define ENABLE_PSEUDO_REQUEST_TESTS 1

#if ENABLE_PSEUDO_REQUEST_TESTS

#define ENABLE_TIMING_TESTS 0 // timing is not reliable on CI machines

@interface TNLPseudoRequestOperationTest : XCTestCase <TNLRequestRetryPolicyProvider, TNLRequestDelegate>
@end

#define PSEUDO_ORIGIN @"http://www.pseudo.com"
#define PSEUDO_REDIRECT PSEUDO_ORIGIN @"/redirect"
#if ENABLE_TIMING_TESTS
#define TIME_BUFFER (0.25)
#endif

static TNLRequestOperationQueue *sQueue;
static TNLRequestConfiguration *sConfig;
static NSURL *sURL;
static NSHTTPURLResponse *sResponse;
static NSData *sData;

@implementation TNLPseudoRequestOperationTest

+ (void)setUp
{
    sURL = [NSURL URLWithString:PSEUDO_ORIGIN];
    sData = [@"{ garbage : \"data\" }" dataUsingEncoding:NSUTF8StringEncoding];
    sResponse = [[NSHTTPURLResponse alloc] initWithURL:sURL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Header1" : @"Value1" }];

    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.protocolOptions = TNLRequestProtocolOptionPseudo;
    sConfig = [config copy];

    sQueue = [[TNLRequestOperationQueue alloc] initWithIdentifier:@"pseudo.request.test.queue"];
}

+ (void)tearDown
{
    [TNLPseudoURLProtocol unregisterEndpoint:sURL];
    sQueue = nil;
    sConfig = nil;
    sURL = nil;
    sData = nil;
    sResponse = nil;
}

- (void)tearDown
{
    [TNLPseudoURLProtocol unregisterAllEndpoints];
    [super tearDown];
}

- (void)registerCannedResponseWithConfig:(TNLPseudoURLResponseConfig *)config
{
    [TNLPseudoURLProtocol registerURLResponse:sResponse body:sData config:config withEndpoint:sURL];
}

- (void)registerRedirectWithBehavior:(TNLPseudoURLProtocolRedirectBehavior)behavior
{
    NSURL *redirectURL = [NSURL URLWithString:PSEUDO_REDIRECT];
    NSHTTPURLResponse *redirectResponse = [[NSHTTPURLResponse alloc] initWithURL:redirectURL
                                                                      statusCode:302
                                                                     HTTPVersion:@"HTTP/1.1"
                                                                    headerFields:@{ @"Location" : PSEUDO_ORIGIN }];
    TNLPseudoURLResponseConfig *config = [[TNLPseudoURLResponseConfig alloc] init];
    config.redirectBehavior = behavior;
    [TNLPseudoURLProtocol registerURLResponse:redirectResponse body:nil config:config withEndpoint:redirectURL];
}

#pragma mark Tests

- (void)testOperation200
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    [self registerCannedResponseWithConfig:nil];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // 200

    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    XCTAssertEqual(200, response.info.statusCode);
    XCTAssertTrue(response.info.data.length > 0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 0.0, TIME_BUFFER);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperation200_TempSuspension
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    [self registerCannedResponseWithConfig:nil];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Temprorary Suspend

    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue suspend];
    [sQueue enqueueRequestOperation:op];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.1]];
    [sQueue resume];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    XCTAssertEqual(200, response.info.statusCode);
    XCTAssertTrue(response.info.data.length > 0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 1.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 1.0, TIME_BUFFER);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperation200_Delay
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Delay

    pseudoConfig.delay = 1000;
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    XCTAssertEqual(200, response.info.statusCode);
    XCTAssertTrue(response.info.data.length > 0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 1.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 1.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 1.0, TIME_BUFFER);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperation200_Delay_and_Latency
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Latency + Delay

    pseudoConfig.delay = 1000;
    pseudoConfig.latency = 250;
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    XCTAssertEqual(200, response.info.statusCode);
    XCTAssertTrue(response.info.data.length > 0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 1.5, TIME_BUFFER * 2);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 1.5, TIME_BUFFER * 2);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 1.5, TIME_BUFFER * 2);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperation200_Latency
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Latency

    pseudoConfig.latency = 250;
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    XCTAssertEqual(200, response.info.statusCode);
    XCTAssertTrue(response.info.data.length > 0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 0.5, TIME_BUFFER * 2);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 0.5, TIME_BUFFER * 2);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 0.5, TIME_BUFFER * 2);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperation302_Follow
{
    NSURL *redirectURL = [NSURL URLWithString:PSEUDO_REDIRECT];

    [self registerRedirectWithBehavior:TNLPseudoURLProtocolRedirectBehaviorFollowLocation];
    [self registerCannedResponseWithConfig:nil];

    TNLMutableHTTPRequest *request = [[TNLMutableHTTPRequest alloc] initWithURL:redirectURL];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:self];

    // expect redirection

    __block NSURLRequest *fromRequest;
    __block NSURLRequest *toRequest;
    XCTestExpectation *expectRedirect;
    expectRedirect = [self expectationForNotification:@"Redirect" object:op handler:^BOOL(NSNotification *notification) {
        fromRequest = notification.userInfo[@"fromRequest"];
        toRequest = notification.userInfo[@"toRequest"];
        return YES;
    }];

    // expect completion

    __block TNLResponse *response;
    XCTestExpectation *expectComplete;
    expectComplete = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    // enqueue the operation and wait for it to finish

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    // check that the redirect happend correctly

    XCTAssertEqualObjects(PSEUDO_REDIRECT, fromRequest.URL.absoluteString);
    XCTAssertEqualObjects(PSEUDO_ORIGIN, toRequest.URL.absoluteString);
    XCTAssertEqualObjects(sURL, toRequest.URL);
    XCTAssertEqual(response.metrics.attemptCount, (NSUInteger)2);
    XCTAssertEqual(response.metrics.attemptMetrics.firstObject.attemptType, TNLAttemptTypeInitial);
    XCTAssertEqual(response.metrics.attemptMetrics.lastObject.attemptType, TNLAttemptTypeRedirect);

    // check that the completion happened correctly

    XCTAssertEqual(200, response.info.statusCode);
    XCTAssertGreaterThan(response.info.data.length,  0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqualObjects(response, op.response);
}

- (void)testOperation302_FollowIfRegistered
{
    NSURL *redirectURL = [NSURL URLWithString:PSEUDO_REDIRECT];

    [self registerRedirectWithBehavior:TNLPseudoURLProtocolRedirectBehaviorFollowLocationIfRedirectResponseIsRegistered];
    [self registerCannedResponseWithConfig:nil];

    TNLMutableHTTPRequest *request = [[TNLMutableHTTPRequest alloc] initWithURL:redirectURL];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:self];

    // expect redirection

    __block NSURLRequest *fromRequest;
    __block NSURLRequest *toRequest;
    XCTestExpectation *expectRedirect;
    expectRedirect = [self expectationForNotification:@"Redirect" object:op handler:^BOOL(NSNotification *notification) {
        fromRequest = notification.userInfo[@"fromRequest"];
        toRequest = notification.userInfo[@"toRequest"];
        return YES;
    }];

    // expect completion

    __block TNLResponse *response;
    XCTestExpectation *expectComplete;
    expectComplete = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    // enqueue the operation and wait for it to finish

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    // check that the redirect happend correctly

    XCTAssertEqualObjects(PSEUDO_REDIRECT, fromRequest.URL.absoluteString);
    XCTAssertEqualObjects(PSEUDO_ORIGIN, toRequest.URL.absoluteString);
    XCTAssertEqualObjects(sURL, toRequest.URL);
    XCTAssertEqual(response.metrics.attemptCount, (NSUInteger)2);
    XCTAssertEqual(response.metrics.attemptMetrics.firstObject.attemptType, TNLAttemptTypeInitial);
    XCTAssertEqual(response.metrics.attemptMetrics.lastObject.attemptType, TNLAttemptTypeRedirect);

    // check that the completion happened correctly

    XCTAssertEqual(200, response.info.statusCode);
    XCTAssertGreaterThan(response.info.data.length,  0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqualObjects(response, op.response);
}

- (void)testOperation302_DontFollowIfNotRegistered
{
    NSURL *redirectURL = [NSURL URLWithString:PSEUDO_REDIRECT];

    [self registerRedirectWithBehavior:TNLPseudoURLProtocolRedirectBehaviorFollowLocationIfRedirectResponseIsRegistered];

    TNLMutableHTTPRequest *request = [[TNLMutableHTTPRequest alloc] initWithURL:redirectURL];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:self];

    // expect completion

    __block TNLResponse *response;
    XCTestExpectation *expectComplete;
    expectComplete = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    // enqueue the operation and wait for it to finish

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    // check that the redirect did not happen

    XCTAssertEqual(response.metrics.attemptCount, (NSUInteger)1);
    XCTAssertEqual(response.metrics.attemptMetrics.firstObject.attemptType, TNLAttemptTypeInitial);

    // check that the completion happened correctly

    XCTAssertEqual(302, response.info.statusCode);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqualObjects(response, op.response);
    XCTAssertEqualObjects([response.info valueForResponseHeaderField:@"Location"], PSEUDO_ORIGIN);
}

- (void)testOperation302_DontFollow
{
    NSURL *redirectURL = [NSURL URLWithString:PSEUDO_REDIRECT];

    [self registerRedirectWithBehavior:TNLPseudoURLProtocolRedirectBehaviorDontFollowLocation];
    [self registerCannedResponseWithConfig:nil];

    TNLMutableHTTPRequest *request = [[TNLMutableHTTPRequest alloc] initWithURL:redirectURL];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:self];

    // expect completion

    __block TNLResponse *response;
    XCTestExpectation *expectComplete;
    expectComplete = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    // enqueue the operation and wait for it to finish

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    // check that the redirect did not happen

    XCTAssertEqual(response.metrics.attemptCount, (NSUInteger)1);
    XCTAssertEqual(response.metrics.attemptMetrics.firstObject.attemptType, TNLAttemptTypeInitial);

    // check that the completion happened correctly

    XCTAssertEqual(302, response.info.statusCode);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqualObjects(response, op.response);
    XCTAssertEqualObjects([response.info valueForResponseHeaderField:@"Location"], PSEUDO_ORIGIN);
}

- (void)testOperationError_AttemptTimeout
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Attempt Timeout (own by NSURL stack and uses a fairly sizeable leeway)

    mConfig.attemptTimeout = 1.0;
    mConfig.operationTimeout = 4.0;
    pseudoConfig.latency = 1500;
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateFailed);

    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationAttemptTimedOut);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 1.0, 1.0);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 1.0, 1.0);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 1.0, 1.0);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperationError_OperationTimeout
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Operation Timeout

    mConfig.attemptTimeout = 1.0;
    mConfig.operationTimeout = 2.0;
    mConfig.retryPolicyProvider = self;
    pseudoConfig.latency = 1500;
    // [mRequest setValue:@"2000" forHTTPHeaderField:@"RETRY_DELAY"];
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateFailed);

    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationOperationTimedOut);
    XCTAssertEqual(response, op.response, @"%@ vs %@", response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 1.5, 1.0);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 1.5, 1.0);
#endif
    XCTAssertEqual(2UL, response.metrics.attemptCount);
}

- (void)testOperationError_OperationTimeout2
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Operation Timeout 2

    mConfig.attemptTimeout = 1.0;
    mConfig.operationTimeout = 2.0;
    mConfig.retryPolicyProvider = self;
    pseudoConfig.latency = 1500;
    [mRequest setValue:@"2000" forHTTPHeaderField:@"RETRY_DELAY"];
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateFailed);

    XCTAssertNotEqual(response.operationError.code, TNLErrorCodeRequestOperationOperationTimedOut);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 1.5, TIME_BUFFER * 2);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 1.5, TIME_BUFFER * 2);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 1.5, TIME_BUFFER * 2);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperationError_OperationTimeout3
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Operation Timeout 3

    pseudoConfig.latency = 1500;
    [mRequest removeAllValuesForHTTPHeaderField:@"RETRY_DELAY"];
    mConfig.attemptTimeout = 3.0;
    mConfig.operationTimeout = 1.2;
    mConfig.retryPolicyProvider = self;
    // [mRequest setValue:@"2000" forHTTPHeaderField:@"RETRY_DELAY"];
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateFailed);

    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationOperationTimedOut);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 1.2, TIME_BUFFER + .1);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 1.2, TIME_BUFFER + .1);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 1.2, TIME_BUFFER + .1);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperationError_Disconnect
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;
    NSError *expectedError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil];

    // Disconnect

    pseudoConfig.failureError = expectedError;
    pseudoConfig.delay = 1000;
    pseudoConfig.latency = 250;
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateFailed);

    XCTAssertEqual(0, response.info.statusCode);
    XCTAssertNotNil(response.operationError);
    XCTAssertEqualObjects(expectedError.domain, response.operationError.domain);
    XCTAssertEqual(expectedError.code, response.operationError.code);
    XCTAssertEqual(response, op.response);
}

- (void)testOperation404
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // 404

    pseudoConfig.statusCode = 404;
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateSucceeded);

    XCTAssertEqual(404, response.info.statusCode);
    XCTAssertTrue(response.info.data.length > 0);
    XCTAssertEqual(1.0, op.downloadProgress);
    XCTAssertEqual(1.0, op.uploadProgress);
    XCTAssertNil(response.operationError);
    XCTAssertEqual(response, op.response);

#if ENABLE_TIMING_TESTS
    XCTAssertEqualWithAccuracy(response.metrics.queuedDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.allAttemptsDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.currentAttemptDuration, 0.0, TIME_BUFFER);
    XCTAssertEqualWithAccuracy(response.metrics.totalDuration, 0.0, TIME_BUFFER);
#endif
    XCTAssertEqual(1UL, response.metrics.attemptCount);
}

- (void)testOperation404_Cancel
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Cancel

    pseudoConfig.delay = 1000;
    pseudoConfig.statusCode = 404;
    mConfig.retryPolicyProvider = self;
    [self registerCannedResponseWithConfig:pseudoConfig];
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
    [op cancelWithSource:@"FORCE_CANCEL_SOURCE"];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertTrue(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateCancelled);

    XCTAssertEqual(0, response.info.statusCode);
    XCTAssertNotNil(response.operationError);
    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationCancelled);
    XCTAssertEqualObjects(response.operationError.userInfo[TNLErrorCancelSourceKey], @"FORCE_CANCEL_SOURCE");
    XCTAssertEqual(response, op.response);
}

- (void)testOperation404_EarlyCancel1
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Early Cancel 1

    mConfig.retryPolicyProvider = self;
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [op cancelWithSource:@"FORCE_CANCEL_SOURCE"];
    [sQueue enqueueRequestOperation:op];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertTrue(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateCancelled);

    XCTAssertEqual(0, response.info.statusCode);
    XCTAssertNotNil(response.operationError);
    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationCancelled);
    XCTAssertEqualObjects(response.operationError.userInfo[TNLErrorCancelSourceKey], @"FORCE_CANCEL_SOURCE");
    XCTAssertEqual(response, op.response);
}

- (void)testOperation404_EarlyCancel2
{
    TNLMutableRequestConfiguration *mConfig = [sConfig mutableCopy];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:sURL];

    __block TNLResponse *response;
    TNLRequestOperation *op;
    XCTestExpectation *expect;

    // Early Cancel 2

    mConfig.retryPolicyProvider = self;
    op = [TNLRequestOperation operationWithRequest:mRequest configuration:mConfig delegate:self];
    expect = [self expectationForNotification:@"Complete" object:op handler:^BOOL(NSNotification *notification) {
        response = notification.userInfo[@"response"];
        return YES;
    }];

    XCTAssertFalse(op.isCancelled);
    XCTAssertFalse(op.isFinished);
    XCTAssertFalse(op.isExecuting);
    XCTAssertEqual(op.state, TNLRequestOperationStateIdle);

    [sQueue enqueueRequestOperation:op];
    [op cancelWithSource:@"FORCE_CANCEL_SOURCE"];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertTrue(op.isCancelled);
    XCTAssertFalse(op.isExecuting);
    XCTAssertTrue(op.isFinished);
    XCTAssertEqual(op.state, TNLRequestOperationStateCancelled);

    XCTAssertEqual(0, response.info.statusCode);
    XCTAssertNotNil(response.operationError);
    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationCancelled);
    XCTAssertEqualObjects(response.operationError.userInfo[TNLErrorCancelSourceKey], @"FORCE_CANCEL_SOURCE");
    XCTAssertEqual(response, op.response);
}

#pragma mark Retry Policy

- (BOOL)tnl_shouldRetryRequestOperation:(TNLRequestOperation *)op withResponse:(TNLResponse *)response
{
    return response.info.statusCode != 200;
}

- (NSTimeInterval)tnl_delayBeforeRetryForRequestOperation:(TNLRequestOperation *)op withResponse:(TNLResponse *)response
{
    return [[[op.originalRequest.allHTTPHeaderFields tnl_objectsForCaseInsensitiveKey:@"RETRY_DELAY"] firstObject] integerValue];
}

#pragma mark TNLRequestDelegate

- (void)tnl_requestOperation:(TNLRequestOperation *)op didRedirectFromURLRequest:(NSURLRequest *)fromRequest toURLRequest:(NSURLRequest *)toRequest
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"Redirect" object:op userInfo:@{ @"fromRequest" : fromRequest, @"toRequest" : toRequest }];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteWithResponse:(TNLResponse *)response
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"Complete" object:op userInfo:@{ @"response" : response }];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op hydrateRequest:(id<TNLRequest>)request completion:(TNLRequestHydrateCompletionBlock)complete
{
    complete(request, nil);
}

@end

#endif // ENABLE_PSEUDO_REQUEST_TESTS

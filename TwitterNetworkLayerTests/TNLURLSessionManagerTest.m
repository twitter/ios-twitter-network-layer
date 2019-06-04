//
//  TNLURLSessionManagerTest.m
//  TwitterNetworkLayer
//
//  Created by Nolan on 4/1/19.
//  Copyright © 2019 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TNLPseudoURLProtocol.h"
#import "TNLRequestOperation.h"
#import "TNLRequestOperationQueue.h"
#import "TNLURLSessionManager.h"


#define kFAKE_URL @"https://www.dummy.com/fake/url.html"

@interface TNLURLSessionManagerTest : XCTestCase
@end

@implementation TNLURLSessionManagerTest

+ (void)setUp
{
    [super setUp];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:kFAKE_URL]
                                                              statusCode:200
                                                             HTTPVersion:@"http/1.1"
                                                            headerFields:nil];
    NSData *data = [@"success" dataUsingEncoding:NSUTF8StringEncoding];
    [TNLPseudoURLProtocol registerURLResponse:response
                                         body:data
                                 withEndpoint:response.URL];
}

+ (void)tearDown
{
    [TNLPseudoURLProtocol unregisterEndpoint:[NSURL URLWithString:kFAKE_URL]];

    [super tearDown];
}

- (void)setUp
{
}

- (void)tearDown
{
    [TNLGlobalConfiguration sharedInstance].URLSessionInactivityThreshold = -1;
    [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions = 0;
}

- (void)testAddingAndPruningSessions
{
    __block NSUInteger prevForegroundSessionCount = 0;
    __block NSUInteger prevBackgroundSessionCount = 0;
    __block NSUInteger currentForegroundSessionCount = 0;
    __block NSUInteger currentBackgroundSessionCount = 0;
    NSURL *url = [NSURL URLWithString:kFAKE_URL];
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.protocolOptions |= TNLRequestProtocolOptionPseudo;
    TNLRequestOperation *op = nil;
    XCTestExpectation *expectation = nil;

    // Forcibly prune all sessions (must do in order to ensure we know what sessions are used)

    [TNLGlobalConfiguration sharedInstance].URLSessionInactivityThreshold = 0.0;
    [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions = TNLGlobalConfigurationURLSessionPruneOptionNow;

    expectation = [self expectationWithDescription:@"Wait For New NSURLSessions after failed Prune"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertEqual(currentForegroundSessionCount, 0);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Initial sessions

    expectation = [self expectationWithDescription:@"Wait For Initial List of NSURLSessions"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        prevForegroundSessionCount = foregroundSessions.count;
        prevBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    // Add a session

    op = [TNLRequestOperation operationWithURL:url
                                 configuration:config
                                      delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For New NSURLSessions"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertGreaterThan(currentForegroundSessionCount, prevForegroundSessionCount);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Add session, different config

    [config configureAsLowPriority];
    op = [TNLRequestOperation operationWithURL:url
                                 configuration:config
                                      delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For New NSURLSessions"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertGreaterThan(currentForegroundSessionCount, prevForegroundSessionCount);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Change Timeouts, don't change session count

    config.idleTimeout = 10.0;
    config.attemptTimeout = 20.0;
    config.operationTimeout = 30.0;
    op = [TNLRequestOperation operationWithURL:url
                                 configuration:config
                                      delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For More New NSURLSessions"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertEqual(currentForegroundSessionCount, prevForegroundSessionCount);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Forcibly prune specific session

    [[TNLGlobalConfiguration sharedInstance] pruneURLSessionMatchingRequestConfiguration:config
                                                                        operationQueueId:nil];

    expectation = [self expectationWithDescription:@"Wait For New NSURLSessions after Prune"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertLessThan(currentForegroundSessionCount, prevForegroundSessionCount);
    XCTAssertNotEqual(currentForegroundSessionCount, 0);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Forcibly prune all sessions (won't prune due to threshold)

    [TNLGlobalConfiguration sharedInstance].URLSessionInactivityThreshold = -1;
    [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions = TNLGlobalConfigurationURLSessionPruneOptionNow;

    expectation = [self expectationWithDescription:@"Wait For New NSURLSessions after failed Prune"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertNotEqual(currentForegroundSessionCount, 0);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Forcibly prune all sessions (will prune due to zero threshold)

    [TNLGlobalConfiguration sharedInstance].URLSessionInactivityThreshold = 0.0;
    [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions = TNLGlobalConfigurationURLSessionPruneOptionNow;

    expectation = [self expectationWithDescription:@"Wait For New NSURLSessions after full Prune"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertEqual(currentForegroundSessionCount, 0);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

#if TARGET_OS_IOS || TARGET_OS_TVOS

    // Update pruning criteria

    [TNLGlobalConfiguration sharedInstance].URLSessionInactivityThreshold = 0.0;
    [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions = TNLGlobalConfigurationURLSessionPruneOptionOnMemoryWarning | TNLGlobalConfigurationURLSessionPruneOptionOnApplicationBackground;

    // Add a session back

    op = [TNLRequestOperation operationWithURL:url
                                 configuration:config
                                      delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For another New NSURLSessions"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertGreaterThan(currentForegroundSessionCount, prevForegroundSessionCount);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Prune on memory warnings

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For NSURLSessions pruning on memory warning"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertEqual(currentForegroundSessionCount, 0);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Add a session back

    op = [TNLRequestOperation operationWithURL:url
                                 configuration:config
                                      delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For another New NSURLSessions"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertGreaterThan(currentForegroundSessionCount, prevForegroundSessionCount);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

    // Prune on application background

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For NSURLSessions pruning on application background"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertEqual(currentForegroundSessionCount, 0);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;

#endif

    // Add a session, but it is removed immediately

    [TNLGlobalConfiguration sharedInstance].URLSessionInactivityThreshold = 0.0;
    [TNLGlobalConfiguration sharedInstance].URLSessionPruneOptions = TNLGlobalConfigurationURLSessionPruneOptionAfterEveryTask;

    op = [TNLRequestOperation operationWithURL:url
                                 configuration:config
                                      delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; // brief delay

    expectation = [self expectationWithDescription:@"Wait For another New NSURLSessions but it will already be gone"];
    [[TNLURLSessionManager sharedInstance] getAllURLSessions:^(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions) {
        currentForegroundSessionCount = foregroundSessions.count;
        currentBackgroundSessionCount = backgroundSessions.count;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:10.0];

    XCTAssertEqual(currentForegroundSessionCount, 0);
    XCTAssertEqual(currentBackgroundSessionCount, prevBackgroundSessionCount);
    prevForegroundSessionCount = currentForegroundSessionCount;
    prevBackgroundSessionCount = currentBackgroundSessionCount;
}

@end


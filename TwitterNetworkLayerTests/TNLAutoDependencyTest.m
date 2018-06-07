//
//  TNLAutoDependencyTest.m
//  TwitterNetworkLayer
//
//  Created on 9/23/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TNLGlobalConfiguration.h"
#import "TNLHTTPRequest.h"
#import "TNLPseudoURLProtocol.h"
#import "TNLRequestOperationCancelSource.h"
#import "TNLRequestOperationQueue.h"

#define SLEEP_LOOP(sleep) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:(sleep)]]

@interface TNLAutoDependencyTest : XCTestCase
@end

@implementation TNLAutoDependencyTest

- (void)tearDown
{
    [TNLPseudoURLProtocol unregisterAllEndpoints];
    [TNLGlobalConfiguration sharedInstance].operationAutomaticDependencyPriorityThreshold = (TNLPriority)NSIntegerMax;

    [super tearDown];
}

- (void)_run:(TNLRequestOperationQueue *)queue
      slowOp:(TNLRequestOperation *)slowOp
     fastOp1:(TNLRequestOperation *)fastOp1
     fastOp2:(TNLRequestOperation *)fastOp2
cancelMidway:(BOOL)cancelMidway
{
    [queue enqueueRequestOperation:slowOp];
    SLEEP_LOOP(0.25);
    [queue enqueueRequestOperation:fastOp1];
    SLEEP_LOOP(0.25);
    [queue enqueueRequestOperation:fastOp2];

    if (cancelMidway) {
        SLEEP_LOOP(0.25);
        [slowOp cancelWithSource:@"Cancel"];
    }

    [slowOp waitUntilFinishedWithoutBlockingRunLoop];
    [fastOp1 waitUntilFinishedWithoutBlockingRunLoop];
    [fastOp2 waitUntilFinishedWithoutBlockingRunLoop];
}

- (void)testAutoDependency
{
    // Prep

    TNLHTTPRequest *slowRequest = [TNLHTTPRequest GETRequestWithURL:[NSURL URLWithString:@"http://www.dummy.com/slow"] HTTPHeaderFields:nil];
    TNLHTTPRequest *fastRequest = [TNLHTTPRequest GETRequestWithURL:[NSURL URLWithString:@"http://www.dummy.com/fast"] HTTPHeaderFields:nil];

    NSHTTPURLResponse *slowResponse = [[NSHTTPURLResponse alloc] initWithURL:slowRequest.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    NSHTTPURLResponse *fastResponse = [[NSHTTPURLResponse alloc] initWithURL:slowRequest.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];

    NSData *slowData = [@"{response:\"slow\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *fastData = [@"{response:\"fast\"}" dataUsingEncoding:NSUTF8StringEncoding];

    TNLPseudoURLResponseConfig *slowConfig = [[TNLPseudoURLResponseConfig alloc] init];
    slowConfig.delay = 1750 /*ms*/;
    TNLPseudoURLResponseConfig *fastConfig = nil;

    [TNLPseudoURLProtocol registerURLResponse:slowResponse
                                         body:slowData
                                       config:slowConfig
                                 withEndpoint:slowRequest.URL];
    [TNLPseudoURLProtocol registerURLResponse:fastResponse
                                         body:fastData
                                       config:fastConfig
                                 withEndpoint:fastRequest.URL];

    TNLMutableRequestConfiguration *requestConfig = [TNLMutableRequestConfiguration defaultConfiguration];
    requestConfig.protocolOptions = TNLRequestProtocolOptionPseudo;
    TNLRequestOperationQueue *queue = [TNLRequestOperationQueue defaultOperationQueue];
    NSMutableArray<TNLRequestOperation *> *completionOrder = [[NSMutableArray alloc] init];
    TNLRequestDidCompleteBlock completeBlock = ^(TNLRequestOperation *op, TNLResponse *response) {
        [completionOrder addObject:op];
    };
    TNLRequestOperation *slowOp = nil;
    TNLRequestOperation *fastOp1 = nil;
    TNLRequestOperation *fastOp2 = nil;

#define RESET_TEST() \
    do { \
        [completionOrder removeAllObjects]; \
        slowOp = [TNLRequestOperation operationWithRequest:slowRequest configuration:requestConfig completion:completeBlock]; \
        slowOp.priority = TNLPriorityVeryHigh; \
        fastOp1 = [TNLRequestOperation operationWithRequest:fastRequest configuration:requestConfig completion:completeBlock]; \
        fastOp2 = [TNLRequestOperation operationWithRequest:fastRequest configuration:requestConfig completion:completeBlock]; \
    } while (0)

    // Test No Auto Dependency

    RESET_TEST();

    [TNLGlobalConfiguration sharedInstance].operationAutomaticDependencyPriorityThreshold = (TNLPriority)NSIntegerMax;

    [self _run:queue
        slowOp:slowOp
       fastOp1:fastOp1
       fastOp2:fastOp2
  cancelMidway:NO];

    XCTAssertEqual(completionOrder.count, (NSUInteger)3);
    XCTAssertEqualObjects([completionOrder objectAtIndex:2], slowOp, @"%@", completionOrder);

    // Test With Auto Dependency

    RESET_TEST();

    [TNLGlobalConfiguration sharedInstance].operationAutomaticDependencyPriorityThreshold = TNLPriorityHigh;

    [self _run:queue
        slowOp:slowOp
       fastOp1:fastOp1
       fastOp2:fastOp2
  cancelMidway:NO];

    XCTAssertEqual(completionOrder.count, (NSUInteger)3);
    XCTAssertEqualObjects([completionOrder objectAtIndex:0], slowOp, @"%@", completionOrder);

    // Test With Auto Dependency (Cancel)

    RESET_TEST();

    [TNLGlobalConfiguration sharedInstance].operationAutomaticDependencyPriorityThreshold = TNLPriorityHigh;

    [self _run:queue
        slowOp:slowOp
       fastOp1:fastOp1
       fastOp2:fastOp2
  cancelMidway:YES];

    XCTAssertEqual(completionOrder.count, (NSUInteger)3);
    XCTAssertEqualObjects([completionOrder objectAtIndex:0], slowOp, @"%@", completionOrder);
}

@end

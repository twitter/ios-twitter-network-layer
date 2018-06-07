//
//  TNLNetworkTests.m
//  TwitterNetworkLayer
//
//  Created on 10/27/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLNetwork.h"

@import XCTest;

@interface TNLNetworkTests : XCTestCase
@end

@implementation TNLNetworkTests

- (XCTestExpectation *)_incrementExpectation
{
    return [self expectationForNotification:TNLNetworkExecutingNetworkConnectionsDidUpdateNotification object:nil handler:^BOOL(NSNotification *note) {
        return [note.userInfo[TNLNetworkExecutingNetworkConnectionsExecutingKey] boolValue] == YES;
    }];
}

- (XCTestExpectation *)_decrementExpectation
{
    return [self expectationForNotification:TNLNetworkExecutingNetworkConnectionsDidUpdateNotification object:nil handler:^BOOL(NSNotification *note) {
        return [note.userInfo[TNLNetworkExecutingNetworkConnectionsExecutingKey] boolValue] == NO;
    }];
}

- (void)testGlobalExecutingNetworkConnections
{
    XCTestExpectation *incrementExpectation;
    XCTestExpectation *decrementExpectation;

    incrementExpectation = [self _incrementExpectation];
    [TNLNetwork incrementExecutingNetworkConnections];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];

    decrementExpectation = [self _decrementExpectation];
    [TNLNetwork decrementExecutingNetworkConnections];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];

    incrementExpectation = [self _incrementExpectation];
    for (NSUInteger i = 0; i < 5; i++) {
        [TNLNetwork incrementExecutingNetworkConnections];
    }
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];

    decrementExpectation = [self _decrementExpectation];
    for (NSUInteger i = 0; i < 5; i++) {
        [TNLNetwork decrementExecutingNetworkConnections];
    }
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];

    incrementExpectation = [self _incrementExpectation];
    [TNLNetwork incrementExecutingNetworkConnections];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];

    decrementExpectation = [self _decrementExpectation];
    [TNLNetwork decrementExecutingNetworkConnections];
    [self waitForExpectationsWithTimeout:5.0 handler:NULL];

    (void)incrementExpectation;
    (void)decrementExpectation;
}

@end

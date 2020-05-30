//
//  TNLAttemptMetaDataTest.m
//  TwitterNetworkLayer
//
//  Created by Kevin Goodier on 05/12/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLAttemptMetaData_Project.h"

@import XCTest;

@interface TNLAttemptMetaDataTest : XCTestCase

@end

@implementation TNLAttemptMetaDataTest

- (void)testHasAccessor
{
    TNLAttemptMetaData *metaData = [[TNLAttemptMetaData alloc] init];

    XCTAssertFalse(metaData.hasServerResponseTime);
    metaData.serverResponseTime = 5;
    XCTAssertTrue(metaData.hasServerResponseTime);
}

- (void)testGetAndSetReference
{
    TNLAttemptMetaData *metaData = [[TNLAttemptMetaData alloc] init];

    XCTAssertFalse(metaData.hasHTTPVersion);
    XCTAssertNil(metaData.HTTPVersion);

    metaData.HTTPVersion = @"1.1";

    XCTAssertTrue(metaData.hasHTTPVersion);
    XCTAssertEqualObjects(metaData.HTTPVersion, @"1.1");
}

- (void)testGetAndSetNilReference
{
    TNLAttemptMetaData *metaData = [[TNLAttemptMetaData alloc] init];

    XCTAssertFalse(metaData.hasHTTPVersion);
    XCTAssertNil(metaData.HTTPVersion);

    metaData.HTTPVersion = nil;

    XCTAssertFalse(metaData.hasHTTPVersion);
    XCTAssertNil(metaData.HTTPVersion);
}

- (void)testClearReference
{
    TNLAttemptMetaData *metaData = [[TNLAttemptMetaData alloc] init];
    metaData.HTTPVersion = @"1.1";
    metaData.HTTPVersion = nil;

    XCTAssertFalse(metaData.hasHTTPVersion);
    XCTAssertNil(metaData.HTTPVersion);
}

- (void)testGetAndSetPrimitive
{
    TNLAttemptMetaData *metaData = [[TNLAttemptMetaData alloc] init];

    XCTAssertFalse(metaData.hasServerResponseTime);
    XCTAssertEqual(metaData.serverResponseTime, 0);

    metaData.serverResponseTime = 5;

    XCTAssertTrue(metaData.hasServerResponseTime);
    XCTAssertEqual(metaData.serverResponseTime, 5);
}

- (void)testEquals
{
    TNLAttemptMetaData *metaData1 = [[TNLAttemptMetaData alloc] init];
    TNLAttemptMetaData *metaData2 = [[TNLAttemptMetaData alloc] init];
    XCTAssertFalse([metaData1 isEqual:nil]);
    XCTAssertTrue([metaData1 isEqual:metaData2]);

    metaData1.HTTPVersion = @"1.1";
    XCTAssertFalse([metaData1 isEqual:metaData2]);

    metaData2.HTTPVersion = @"1.1";
    XCTAssertTrue([metaData1 isEqual:metaData2]);

    metaData1.serverResponseTime = 5;
    XCTAssertFalse([metaData1 isEqual:metaData2]);

    metaData2.serverResponseTime = 5;
    XCTAssertTrue([metaData1 isEqual:metaData2]);

    metaData2.HTTPVersion = nil;
    XCTAssertFalse([metaData1 isEqual:metaData2]);
}

@end

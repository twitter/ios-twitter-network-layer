//
//  NSDictionary+TNLAdditionsTest.m
//  TwitterNetworkLayer
//
//  Created on 10/27/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSDictionary+TNLAdditions.h"

@import XCTest;

@interface NSDictionary_TNLAdditionsTest : XCTestCase

@end

@implementation NSDictionary_TNLAdditionsTest

- (void)testCaseInsensitiveKeyMethods
{
    NSSet *set;
    NSMutableDictionary *d = [@{ @"one" : @"1", @"TWO" : @"2", @"tHrEe" : @"3", @"three" : @"3...again" } mutableCopy];

    // Objects for key
    XCTAssertEqual(0UL, [d tnl_objectsForCaseInsensitiveKey:@"dummy"].count);

    XCTAssertEqualObjects(@[ @"1" ], [d tnl_objectsForCaseInsensitiveKey:@"ONE"]);
    XCTAssertEqualObjects(@[ @"1" ], [d tnl_objectsForCaseInsensitiveKey:@"one"]);
    XCTAssertEqualObjects(@[ @"1" ], [d tnl_objectsForCaseInsensitiveKey:@"oNe"]);

    XCTAssertEqualObjects(@[ @"2" ], [d tnl_objectsForCaseInsensitiveKey:@"two"]);

    set = [NSSet setWithArray:@[ @"3" , @"3...again" ]];
    XCTAssertEqualObjects(set, [NSSet setWithArray:[d tnl_objectsForCaseInsensitiveKey:@"THREE"]]);

    // Keys for key
    set = [NSSet setWithArray:@[ @"tHrEe", @"three" ]];
    XCTAssertEqualObjects(set, [d tnl_keysMatchingCaseInsensitiveKey:@"THREE"]);

    XCTAssertEqualObjects(@[@"one"], [d tnl_keysMatchingCaseInsensitiveKey:@"ONE"].allObjects);
    XCTAssertEqualObjects(@[@"TWO"], [d tnl_keysMatchingCaseInsensitiveKey:@"two"].allObjects);

    XCTAssertEqual(0UL, [d tnl_keysMatchingCaseInsensitiveKey:@"dummy"].count);

    // Set
    [d tnl_setObject:@1 forCaseInsensitiveKey:@"ONE"];
    XCTAssertEqualObjects(@[@"ONE"], [d tnl_keysMatchingCaseInsensitiveKey:@"one"].allObjects);
    XCTAssertEqualObjects(@[ @1 ], [d tnl_objectsForCaseInsensitiveKey:@"one"]);

    // Remove
    [d tnl_removeObjectsForCaseInsensitiveKey:@"THREE"];
    XCTAssertEqual(0UL, [d tnl_objectsForCaseInsensitiveKey:@"three"].count);
}

@end

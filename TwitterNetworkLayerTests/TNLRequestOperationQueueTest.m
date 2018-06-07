//
//  TNLRequestOperationQueueTest.m
//  TwitterNetworkLayer
//
//  Created on 5/1/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TNLRequestOperationQueue.h"

@import XCTest;

@interface TNLRequestOperationQueueTest : XCTestCase

@end

@implementation TNLRequestOperationQueueTest

- (void)testCreateQueue
{
    // The identifier to use for identifying this specific `TNLRequestOperationQueue`.  This identifier MUST be unique among all running queues.  Must be in URL host form.  Any _identifier_ that is not ASCII alpha-numeric with optional `'.'` seperators, is `nil` or is zero _length_ will throw an exception.  If an existing`TNLRequestOperationQueue` already has the given identifier, an exception will be thrown.

    TNLRequestOperationQueue *queue = nil;

    XCTAssertNoThrow((queue = [[TNLRequestOperationQueue alloc] initWithIdentifier:@"abc"]));
    XCTAssertNotNil(queue);
    queue = nil;

    XCTAssertNoThrow((queue = [[TNLRequestOperationQueue alloc] initWithIdentifier:@"abcdefghijklmnopqrstuvqxyz.ABCDEFGHIJKLMNOPQRSTUVWXYZ.0123456789"]));
    XCTAssertNotNil(queue);
    queue = nil;

    XCTAssertThrows((queue = [[TNLRequestOperationQueue alloc] initWithIdentifier:@""]));
    XCTAssertNil(queue);
    queue = nil;

    XCTAssertThrows((queue = [[TNLRequestOperationQueue alloc] initWithIdentifier:(NSString * __nonnull)nil]));
    XCTAssertNil(queue);
    queue = nil;

    XCTAssertThrows((queue = [[TNLRequestOperationQueue alloc] initWithIdentifier:@"abcdefghijklmnopqrstuvqxyz-ABCDEFGHIJKLMNOPQRSTUVWXYZ-0123456789"]));
    XCTAssertNil(queue);
    queue = nil;

    // dupe queue
    TNLRequestOperationQueue *otherQueue = [[TNLRequestOperationQueue alloc] initWithIdentifier:@"1"];
    XCTAssertThrows((queue = [[TNLRequestOperationQueue alloc] initWithIdentifier:otherQueue.identifier]));
    XCTAssertNil(queue);
    queue = nil;
    otherQueue = nil;
}

@end

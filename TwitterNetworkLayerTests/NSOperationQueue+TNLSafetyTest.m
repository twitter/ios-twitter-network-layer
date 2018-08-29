//
//  NSOperationQueue+TNLSafetyTest.m
//  TwitterNetworkLayer
//
//  Created on 10/6/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#include <stdatomic.h>

#import "NSOperationQueue+TNLSafety.h"
#import "TNLSafeOperation.h"

@import XCTest;

@interface TNLOperationSafetyGuard : NSObject
- (NSSet *)operations;
+ (nullable instancetype)operationSafetyGuard;
@end

@interface TestAsyncOperation : TNLSafeOperation
@property (nonatomic, copy) dispatch_block_t block;
@property (atomic, getter=isExecuting) BOOL executing;
@property (atomic, getter=isFinished) BOOL finished;
@property (nonatomic, copy) NSString *descriptiveString;
@end

@interface NSOperationQueue_TNLSafetyTest : XCTestCase

@end

@implementation NSOperationQueue_TNLSafetyTest

- (void)testSafety
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;

    NSLog(@"Starting 100 operations");

    const int32_t totalOps = 100;
    __block volatile atomic_int_fast32_t runCount = 0;
    __block volatile atomic_int_fast32_t completedCount = 0;
    TestAsyncOperation *op = nil;
    for (NSUInteger i = 0; (NSUInteger)i < totalOps; i++) {
        BOOL cancel = i % 2 == 0;
        BOOL longBlock = i % 3 == 0;
        op = [[TestAsyncOperation alloc] init];
        op.descriptiveString = [NSString stringWithFormat:@"[%@%@, %tu]", cancel ? @"cancelled, " : @"", longBlock ? @"long" : @"short", i];
        op.completionBlock = ^{
            atomic_fetch_add(&completedCount, 1);
        };
        op.block = ^{
            atomic_fetch_add(&runCount, 1);
            if (longBlock) {
                // make sure some ops take long enough that they won't finish faster than
                // tnl_safeAddOperation: takes to start observing an op
                sleep(2);
            }
        };
        if (cancel) {
            // have half the ops with isFinished == YES before they are even enqueued
            [op cancel];
        }
        [queue tnl_safeAddOperation:op];
    }

    NSLog(@"100 operations started");

    NSSet *stillObservedOperations = nil;

    // Loop to give time for async finishing of ops in NSOperationQueue
    for (NSUInteger i = 0; i < 20; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        if (queue.operationCount == 0) {

            // Loop to give time for async removal of observed operations
            for (NSUInteger j = 0; j < 20; j++) {
                stillObservedOperations = [TNLOperationSafetyGuard operationSafetyGuard].operations;
                if (stillObservedOperations.count == 0) {

                    // Loop to give time for async calling of completion blocks
                    for (NSUInteger k = 0; k < 20; k++) {
                        if (completedCount == totalOps) {
                            break;
                        }
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
                    }

                    break;
                }
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
            }

            break;
        }
    }

    XCTAssertEqual((totalOps / 2), (int32_t)atomic_load(&runCount), @"Exactly 50%% of the ops should have actually run");
    XCTAssertEqual((int32_t)atomic_load(&completedCount), totalOps, @"All ops should have had their completionBlock called");
    XCTAssertEqual(queue.operationCount, (NSUInteger)0, @"The operation queue should be empty (all ops finished)");
    XCTAssertEqual(stillObservedOperations.count, (NSUInteger)0, @"The support object that KVO observes the ops should have removed observation for all ops (they all finished)");

    for (TestAsyncOperation *testOp in stillObservedOperations) {
        NSLog(@"Still observing op: %@ - %@", testOp.descriptiveString, testOp);
    }
}

@end

@implementation TestAsyncOperation

@synthesize finished = _finishedTest;
@synthesize executing = _executingTest;

- (BOOL)isAsynchronous
{
    return YES;
}

- (void)start
{
    [self willChangeValueForKey:@"isExecuting"];
    self.executing = YES;
    [self didChangeValueForKey:@"isExecuting"];

    if (self.isCancelled) {
        [self finish];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!self.isCancelled) {
            dispatch_block_t block = self.block;
            if (block) {
                block();
            }
        }

        [self finish];
    });
}

- (void)finish
{
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    self.executing = NO;
    self.finished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

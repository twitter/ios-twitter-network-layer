//
//  NSOperationQueue+TNLSafety.m
//  TwitterNetworkLayer
//
//  Created on 8/14/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "NSOperationQueue+TNLSafety.h"
#import "TNL_Project.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const TNLOperationSafetyGuardRemoveOperationAfterFinishedDelay = 2.0;
static NSTimeInterval const TNLOperationSafetyGuardCheckForAlreadyFinishedOperationDelay = 1.0;

@interface TNLOperationSafetyGuard : NSObject
- (void)addOperation:(NSOperation *)op;
- (NSSet *)operations;
+ (nullable instancetype)operationSafetyGuard;
@end

@implementation NSOperationQueue (TNLSafety)

- (void)tnl_safeAddOperation:(NSOperation *)op
{
    TNLOperationSafetyGuard *guard = [TNLOperationSafetyGuard operationSafetyGuard];
    if (guard) {
        [guard addOperation:op];
    }
    [self addOperation:op];
}

@end

@implementation TNLOperationSafetyGuard
{
    dispatch_queue_t _queue;
    NSMutableSet *_operations;
}

+ (nullable instancetype)operationSafetyGuard
{
    static TNLOperationSafetyGuard *sGuard = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (tnl_available_ios_9) {
            // no guard needed
        } else {
            sGuard = [[TNLOperationSafetyGuard alloc] init];
        }
    });
    return sGuard;
}

- (instancetype)init
{
    if (self = [super init]) {
        _operations = [[NSMutableSet alloc] init];
        _queue = dispatch_queue_create("NSOperationQueue.tnl.safety", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    }
    return self;
}

- (void)dealloc
{
    for (NSOperation *op in _operations) {
        [op removeObserver:self forKeyPath:@"isFinished"];
    }
}

- (NSSet *)operations
{
    __block NSSet *operations;
    dispatch_sync(_queue, ^{
        operations = [self->_operations copy];
    });
    return operations;
}

- (void)addOperation:(NSOperation *)op
{
    if (!op.isAsynchronous || op.isFinished) {
        return;
    }

    dispatch_async(_queue, ^{
        [self->_operations addObject:op];
        [op addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:NULL];

        // There are race conditions where the isFinished KVO may never be observed.
        // Use this async check to weed out any early finishing operations that we didn't observe finishing.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TNLOperationSafetyGuardCheckForAlreadyFinishedOperationDelay * NSEC_PER_SEC)), self->_queue, ^{
            if (op.isFinished) {
                // Call our KVO observer to unify the code path for removing the observer
                [self observeValueForKeyPath:@"isFinished" ofObject:op change:@{ NSKeyValueChangeNewKey : @YES } context:NULL];
            }
        });
    });
}

- (void)_tnl_background_removeOperation:(NSOperation *)op
{
    // protect against redundant observer removal
    if ([self->_operations containsObject:op]) {
        [op removeObserver:self forKeyPath:@"isFinished"];
        [self->_operations removeObject:op];
    }
}

/**
 We use KVO to determine when an operation is finished because:

 1) we cannot force all implementations of NSOperation to implement code that needs to execute when finishing
 2) swizzling -didChangeValueForKey: would lead to a MAJOR performance degredation according to Apple developers
 */
- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary *)change context:(nullable void *)context
{
    if ([keyPath isEqualToString:@"isFinished"] && [change[NSKeyValueChangeNewKey] boolValue]) {
        NSOperation *op = object;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TNLOperationSafetyGuardRemoveOperationAfterFinishedDelay * NSEC_PER_SEC)), _queue, ^{
            [self _tnl_background_removeOperation:op];
        });
    }
}

@end

NS_ASSUME_NONNULL_END


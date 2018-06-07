//
//  TNLTimeoutOperation.m
//  TwitterNetworkLayer
//
//  Created on 12/7/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#include <stdatomic.h>

#import "TNL_Project.h"
#import "TNLTimeoutOperation.h"

#define SELF_ARG PRIVATE_SELF(TNLTimeoutOperation)

NS_ASSUME_NONNULL_BEGIN

@implementation TNLTimeoutOperation
{
    volatile atomic_bool _executingFlag;
    volatile atomic_bool _finishedFlag;
}

- (instancetype)initWithTimeoutDuration:(NSTimeInterval)timeout
{
    if (self = [super init]) {
        _timeoutDuration = timeout;
        atomic_init(&_finishedFlag, false);
        atomic_init(&_executingFlag, false);
    }
    return self;
}

- (BOOL)isExecuting
{
    return atomic_load(&_executingFlag);
}

- (BOOL)isFinished
{
    return atomic_load(&_finishedFlag);
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (void)start
{
    if (self.isCancelled) {
        [self willChangeValueForKey:@"isFinished"];
        atomic_store(&_finishedFlag, true);
        [self didChangeValueForKey:@"isFinished"];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&_executingFlag, true);
    [self didChangeValueForKey:@"isExecuting"];

    if (_timeoutDuration > 0.0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_timeoutDuration * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            _complete(self);
        });
    } else {
        _complete(self);
    }
}

static void _complete(SELF_ARG)
{
    if (!self) {
        return;
    }

    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&self->_executingFlag, false);
    atomic_store(&self->_finishedFlag, true);
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

NS_ASSUME_NONNULL_END

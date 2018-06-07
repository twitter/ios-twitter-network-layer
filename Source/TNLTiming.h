//
//  TNLTiming.h
//  TwitterNetworkLayer
//
//  Created on 5/12/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// NOTE: conversion can lose precision if conversion would result in overflow.
//       Overflow protection is provided at the sacrifice of precision.
FOUNDATION_EXTERN uint64_t TNLAbsoluteToNanoseconds(uint64_t absolute);
FOUNDATION_EXTERN uint64_t TNLAbsoluteFromNanoseconds(uint64_t nano);

// NOTE: conversion can lose precision for the same reason as TNLAbsoluteToNanoseconds, but
//       also runs the risk of losing precision by converting a 64-bit precision int to a
//       double which has 52 bits of precision.  This is likely always plenty of precision for
//       elapsed durations though (about 285 years to the nearest nanosecond).
FOUNDATION_EXTERN NSTimeInterval TNLAbsoluteToTimeInterval(uint64_t absolute);
FOUNDATION_EXTERN uint64_t TNLAbsoluteFromTimeInterval(NSTimeInterval ti);

static const NSTimeInterval kTNLTimeEpsilon = 0.0005;

// If endTime is 0, mach_absolute_time() will be used in the calculation
FOUNDATION_EXTERN NSTimeInterval TNLComputeDuration(uint64_t startTime, uint64_t endTime);

NS_ASSUME_NONNULL_END


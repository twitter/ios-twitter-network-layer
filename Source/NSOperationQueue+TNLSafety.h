//
//  NSOperationQueue+TNLSafety.h
//  TwitterNetworkLayer
//
//  Created on 8/14/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**

 The entire purpose of the TNLSafety category is to provide additional safety around
 NSOperationQueue due to a race condition in the QoS of NSOperation that definitely affects iOS 8
 and, to a lesser extent, iOS 7.

 Long story short, this category saves from a LOT of crashing.

 The issue was fixed in iOS 9.

 */
@interface NSOperationQueue (TNLSafety)

/**
 Same as `[NSOperationQueue addOperation:]` but with added safety.
 If _op_ returns `YES` for `isAsynchronous`, the operation will be retained for a period that
 extends beyond the lifetime of the operation executing to avoid a crash.
 If called on an OS version that doesn't have the bug, will just pass through to `addOperation:`
 */
- (void)tnl_safeAddOperation:(NSOperation *)op;

@end

NS_ASSUME_NONNULL_END

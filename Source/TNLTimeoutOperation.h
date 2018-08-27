//
//  TNLTimeoutOperation.h
//  TwitterNetworkLayer
//
//  Created on 12/7/17.
//  Copyright © 2017 Twitter. All rights reserved.
//

#import "TNLSafeOperation.h"

/*
 * NOTE: this header is private to TNL
 */

NS_ASSUME_NONNULL_BEGIN

@interface TNLTimeoutOperation : TNLSafeOperation

@property (nonatomic, readonly) NSTimeInterval timeoutDuration;

- (instancetype)initWithTimeoutDuration:(NSTimeInterval)timeout NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

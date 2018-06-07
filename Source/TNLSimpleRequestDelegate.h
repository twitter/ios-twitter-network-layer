//
//  TNLSimpleRequestDelegate.h
//  TwitterNetworkLayer
//
//  Created on 11/25/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLRequestDelegate.h"
#import "TNLRequestOperation.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

@interface TNLSimpleRequestDelegate : NSObject <TNLRequestDelegate>

@property (nonatomic, readonly) TNLRequestDidCompleteBlock didCompleteBlock;

- (instancetype)initWithDidCompleteBlock:(TNLRequestDidCompleteBlock)didCompleteBlock;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

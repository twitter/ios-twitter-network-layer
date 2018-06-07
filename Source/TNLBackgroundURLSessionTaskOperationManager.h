//
//  TNLBackgroundURLSessionTaskOperationManager.h
//  TwitterNetworkLayer
//
//  Created on 8/6/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

/*
 * NOTE: this header is private to TNL
 */

NS_ASSUME_NONNULL_BEGIN

@interface TNLBackgroundURLSessionTaskOperationManager : NSObject

- (void)handleBackgroundURLSessionEvents:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END

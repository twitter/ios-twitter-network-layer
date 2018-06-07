//
//  NSData+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 9/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

/*
 * NOTE: this header is private to TNL
 * TODO: consider exposing this header
 */

NS_ASSUME_NONNULL_BEGIN

@interface NSData (TNLAdditions)
- (NSData *)tnl_safeSubdataNoCopyWithRange:(NSRange)range;
- (NSString *)tnl_hexStringValue;
@end

NS_ASSUME_NONNULL_END

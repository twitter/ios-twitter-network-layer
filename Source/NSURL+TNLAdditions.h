//
//  NSURL+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 12/20/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURL`
 */
@interface NSURL (TNLAdditions)

/**
 Return a new `NSURL` with the host replaced with _newHost_.
 */
- (NSURL *)tnl_URLByReplacingHost:(NSString *)newHost;

@end

NS_ASSUME_NONNULL_END

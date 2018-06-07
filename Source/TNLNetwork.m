//
//  TNLNetwork.m
//  TwitterNetworkLayer
//
//  Created on 9/15/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLNetwork.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const TNLNetworkExecutingNetworkConnectionsDidUpdateNotification = @"TNLNetworkExecutingNetworkConnectionsDidUpdateNotification";
NSString * const TNLNetworkExecutingNetworkConnectionsExecutingKey = @"executing";

NS_ASSUME_NONNULL_END

/*
 @implementation TNLNetwork can be found in TNLRequestOperationQueue.m due to dependencies on statics within that file
 */

//
//  TNLXNetworkHeuristicObserver.h
//  TwitterNetworkLayer
//
//  Created on 1/26/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

@interface TNLXNetworkHeuristicObserver : NSObject <TNLNetworkObserver>

+ (instancetype)sharedInstance;

@end

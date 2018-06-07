//
//  NSURL+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 12/20/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "NSURL+TNLAdditions.h"
#import "TNL_Project.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSURL (TNLAdditions)

- (NSURL *)tnl_URLByReplacingHost:(NSString *)newHost
{
    TNLAssert(newHost);
    NSURLComponents *URLComponents = [[NSURLComponents alloc] initWithURL:self resolvingAgainstBaseURL:NO];
    URLComponents.host = newHost;
    return URLComponents.URL;
}

@end

NS_ASSUME_NONNULL_END

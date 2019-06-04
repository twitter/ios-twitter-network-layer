//
//  TNLRequestOperationCancelSource.m
//  TwitterNetworkLayer
//
//  Created on 10/21/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLRequestOperationCancelSource.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (TNLRequestOperationCancelSource)

- (NSString *)tnl_cancelSourceDescription
{
    return self;
}

@end

@implementation NSError (TNLRequestOperationCancelSource)

- (NSString *)tnl_cancelSourceDescription
{
    return [self description];
}

- (NSError *)tnl_cancelSourceOverrideError
{
    return self;
}

@end

@implementation TNLOperationCancelMethodCancelSource

- (NSString *)tnl_cancelSourceDescription
{
    return @"NSOperation's `cancel` was called";
}

@end

NS_ASSUME_NONNULL_END

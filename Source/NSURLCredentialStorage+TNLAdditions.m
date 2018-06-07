//
//  NSURLCredentialStorage+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 12/5/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLCredentialStorage+TNLAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLSharedCredentialStorageProxy : NSProxy
@end

@implementation NSURLCredentialStorage (TNLAdditions)

+ (NSURLCredentialStorage *)tnl_sharedCredentialStorageProxy
{
    static TNLSharedCredentialStorageProxy *sProxy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProxy = [TNLSharedCredentialStorageProxy alloc];
    });
    return (id)sProxy;
}

@end

@implementation TNLSharedCredentialStorageProxy

- (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    return [[NSURLCredentialStorage sharedCredentialStorage] methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    [invocation invokeWithTarget:[NSURLCredentialStorage sharedCredentialStorage]];
}

@end

NS_ASSUME_NONNULL_END

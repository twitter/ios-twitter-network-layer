//
//  NSHTTPCookieStorage+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 2/9/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "NSHTTPCookieStorage+TNLAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLSharedCookieStorageProxy : NSProxy
@end

@implementation NSHTTPCookieStorage (TNLAdditions)

+ (NSHTTPCookieStorage *)tnl_sharedHTTPCookieStorage
{
    static TNLSharedCookieStorageProxy *sProxy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProxy = [TNLSharedCookieStorageProxy alloc];
    });
    return (id)sProxy;
}

@end

@implementation TNLSharedCookieStorageProxy

- (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    return [[NSHTTPCookieStorage sharedHTTPCookieStorage] methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    [invocation invokeWithTarget:[NSHTTPCookieStorage sharedHTTPCookieStorage]];
}

- (NSString *)description
{
    // NSHTTPCookieStorage has a very severe bug in it's description that can lead to corruption, crashing or an invalid string
    // Let's avoid this in our proxy by overriding it
    // TODO:[nobrien] - investigate swizzling out the description method of NSHTTPCookieStorage for safety
    return [NSString stringWithFormat:@"<%@ %p>", NSStringFromClass([self class]), self];
}

@end

NS_ASSUME_NONNULL_END

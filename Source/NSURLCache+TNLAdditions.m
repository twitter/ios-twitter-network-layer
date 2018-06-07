//
//  NSURLCache+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 8/12/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLCache+TNLAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLImpotentURLCache : NSURLCache
@end

@interface TNLSharedURLCacheProxy : NSProxy
@end

@implementation NSURLCache (TNLAdditions)

+ (NSURLCache *)tnl_impotentURLCache
{
    static TNLImpotentURLCache *sCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCache = [[TNLImpotentURLCache alloc] init];
    });
    return sCache;
}

+ (NSURLCache *)tnl_sharedURLCacheProxy
{
    static TNLSharedURLCacheProxy *sProxy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProxy = [TNLSharedURLCacheProxy alloc];
    });
    return (id)sProxy;
}

@end

@implementation TNLSharedURLCacheProxy

- (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    return [[NSURLCache sharedURLCache] methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    [invocation invokeWithTarget:[NSURLCache sharedURLCache]];
}

@end

@implementation TNLImpotentURLCache

- (id)init
{
    // Don't call super!
    // This object is impotent.
    // Calling super would create an expensive NSURLCache.
    return self;
}

- (id)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity diskPath:(nullable NSString *)path
{
    return [self init];
}

- (nullable NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request
{
    return nil;
}

- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request
{
}

- (void)removeCachedResponseForRequest:(NSURLRequest *)request
{
}

- (void)removeAllCachedResponses
{
}

- (NSUInteger)memoryCapacity
{
    return 0;
}

- (NSUInteger)diskCapacity
{
    return 0;
}

- (void)setMemoryCapacity:(NSUInteger)memoryCapacity
{
}

- (void)setDiskCapacity:(NSUInteger)diskCapacity
{
}

- (NSUInteger)currentMemoryUsage
{
    return 0;
}

- (NSUInteger)currentDiskUsage
{
    return 0;
}

@end

NS_ASSUME_NONNULL_END

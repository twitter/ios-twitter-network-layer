//
//  NSURLCache+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 8/12/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLCache+TNLAdditions.h"
#import "TNLRequestConfiguration_Project.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLImpotentURLCache : NSURLCache
@end

@interface TNLSharedURLCacheProxy : NSProxy
@end

@interface TNLURLCacheDemuxProxy : TNLSharedURLCacheProxy
@end

NSURLCache *TNLGetURLCacheDemuxProxy()
{
    static TNLURLCacheDemuxProxy *sProxy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProxy = [TNLURLCacheDemuxProxy alloc];
    });
    return (id)sProxy;
}

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

@implementation TNLURLCacheDemuxProxy

// Legacy

- (nullable NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(request);
    NSURLCache *cache = TNLUnwrappedURLCache(config.URLCache);
    if (cache) {
        return [cache cachedResponseForRequest:request];
    }
    return nil;
}

- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(request);
    NSURLCache *cache = TNLUnwrappedURLCache(config.URLCache);
    if (cache) {
        [cache storeCachedResponse:cachedResponse forRequest:request];
    }
}

- (void)removeCachedResponseForRequest:(NSURLRequest *)request
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(request);
    NSURLCache *cache = TNLUnwrappedURLCache(config.URLCache);
    if (cache) {
        [cache removeCachedResponseForRequest:request];
    }
}

// Modern

- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse
                forDataTask:(NSURLSessionDataTask *)dataTask
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(dataTask.originalRequest);
    NSURLCache *cache = TNLUnwrappedURLCache(config.URLCache);
    if (cache) {
        [cache storeCachedResponse:cachedResponse
                       forDataTask:dataTask];
    }
}

- (void)getCachedResponseForDataTask:(NSURLSessionDataTask *)dataTask
                   completionHandler:(void (^) (NSCachedURLResponse * _Nullable cachedResponse))completionHandler
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(dataTask.originalRequest);
    NSURLCache *cache = TNLUnwrappedURLCache(config.URLCache);
    if (cache) {
        [cache getCachedResponseForDataTask:dataTask
                          completionHandler:completionHandler];
    } else {
        completionHandler(nil);
    }
}

- (void)removeCachedResponseForDataTask:(NSURLSessionDataTask *)dataTask
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(dataTask.originalRequest);
    NSURLCache *cache = TNLUnwrappedURLCache(config.URLCache);
    if (cache) {
        [cache removeCachedResponseForDataTask:dataTask];
    }
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

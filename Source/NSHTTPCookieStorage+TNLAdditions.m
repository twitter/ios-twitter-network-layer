//
//  NSHTTPCookieStorage+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 2/9/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "NSHTTPCookieStorage+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLRequestConfiguration_Project.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLSharedCookieStorageProxy : NSProxy
@end

@interface TNLHTTPCookieStorageDemuxProxy : TNLSharedCookieStorageProxy
@end

NSHTTPCookieStorage *TNLGetHTTPCookieStorageDemuxProxy()
{
    static TNLHTTPCookieStorageDemuxProxy *sProxy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProxy = [TNLHTTPCookieStorageDemuxProxy alloc];
    });
    return (id)sProxy;
}

@implementation NSHTTPCookieStorage (TNLAdditions)

+ (NSHTTPCookieStorage *)tnl_sharedHTTPCookieStorageProxy
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
    // NSHTTPCookieStorage has a very severe bug in its `description` method that can lead to
    // corruption, crashing or an invalid string.
    // Let's avoid this in our proxy by overriding it
    // TODO:[nobrien] - investigate swizzling out the description method of NSHTTPCookieStorage for safety
    return [NSString stringWithFormat:@"<%@ %p>", NSStringFromClass([self class]), self];
}

@end

@implementation TNLHTTPCookieStorageDemuxProxy

// Legacy is not supported since there isn't a good place to associate the request config with the URL

// Modern - API_AVAILABLE(macos(10.10), ios(8.0), watchos(2.0), tvos(9.0))

- (void)storeCookies:(NSArray<NSHTTPCookie *> *)cookies
             forTask:(NSURLSessionTask *)task
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(task.originalRequest);
    NSHTTPCookieStorage *store = TNLUnwrappedCookieStorage(config.cookieStorage);
    if (store) {
        [store storeCookies:cookies
                    forTask:task];
    }
}

- (void)getCookiesForTask:(NSURLSessionTask *)task
        completionHandler:(void (^) (NSArray<NSHTTPCookie *> * _Nullable cookies))completionHandler
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(task.originalRequest);
    NSHTTPCookieStorage *store = TNLUnwrappedCookieStorage(config.cookieStorage);
    if (store) {
        [store getCookiesForTask:task
               completionHandler:completionHandler];
    } else {
        completionHandler(nil);
    }
}

@end

NS_ASSUME_NONNULL_END

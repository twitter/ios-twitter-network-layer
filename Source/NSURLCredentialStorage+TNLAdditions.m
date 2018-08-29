//
//  NSURLCredentialStorage+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 12/5/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLCredentialStorage+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLRequestConfiguration_Project.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLSharedCredentialStorageProxy : NSProxy
@end

@interface TNLURLCredentialStorageDemuxProxy : TNLSharedCredentialStorageProxy
@end

NSURLCredentialStorage *TNLGetURLCredentialStorageDemuxProxy()
{
    static TNLURLCredentialStorageDemuxProxy *sProxy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProxy = [TNLURLCredentialStorageDemuxProxy alloc];
    });
    return (id)sProxy;
}
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

@implementation TNLURLCredentialStorageDemuxProxy

// Legacy is not supported since there isn't a good place to associate the request config with the protection space

// Modern - API_AVAILABLE(macos(10.10), ios(8.0), watchos(2.0), tvos(9.0))

- (void)getCredentialsForProtectionSpace:(NSURLProtectionSpace *)protectionSpace
                                    task:(NSURLSessionTask *)task
                       completionHandler:(void (^) (NSDictionary<NSString *, NSURLCredential *> * _Nullable credentials))completionHandler
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(task.originalRequest);
    NSURLCredentialStorage *store = TNLUnwrappedURLCredentialStorage(config.URLCredentialStorage);
    if (store) {
        [store getCredentialsForProtectionSpace:protectionSpace
                                           task:task
                              completionHandler:completionHandler];
    } else {
        completionHandler(nil);
    }
}

- (void)setCredential:(NSURLCredential *)credential
   forProtectionSpace:(NSURLProtectionSpace *)protectionSpace
                 task:(NSURLSessionTask *)task
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(task.originalRequest);
    NSURLCredentialStorage *store = TNLUnwrappedURLCredentialStorage(config.URLCredentialStorage);
    if (store) {
        [store setCredential:credential
          forProtectionSpace:protectionSpace
                        task:task];
    }
}

- (void)removeCredential:(NSURLCredential *)credential
      forProtectionSpace:(NSURLProtectionSpace *)protectionSpace
                 options:(nullable NSDictionary<NSString *, id> *)options
                    task:(NSURLSessionTask *)task
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(task.originalRequest);
    NSURLCredentialStorage *store = TNLUnwrappedURLCredentialStorage(config.URLCredentialStorage);
    if (store) {
        [store removeCredential:credential
             forProtectionSpace:protectionSpace
                        options:options
                           task:task];
    }
}
- (void)getDefaultCredentialForProtectionSpace:(NSURLProtectionSpace *)space
                                          task:(NSURLSessionTask *)task
                             completionHandler:(void (^) (NSURLCredential * _Nullable credential))completionHandler
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(task.originalRequest);
    NSURLCredentialStorage *store = TNLUnwrappedURLCredentialStorage(config.URLCredentialStorage);
    if (store) {
        [store getDefaultCredentialForProtectionSpace:space
                                                 task:task
                                    completionHandler:completionHandler];
    } else {
        completionHandler(nil);
    }
}

- (void)setDefaultCredential:(NSURLCredential *)credential
          forProtectionSpace:(NSURLProtectionSpace *)protectionSpace
                        task:(NSURLSessionTask *)task
{
    TNLRequestConfiguration *config = TNLRequestConfigurationGetAssociatedWithRequest(task.originalRequest);
    NSURLCredentialStorage *store = TNLUnwrappedURLCredentialStorage(config.URLCredentialStorage);
    if (store) {
        [store setDefaultCredential:credential
                 forProtectionSpace:protectionSpace
                               task:task];
    }
}

@end

NS_ASSUME_NONNULL_END

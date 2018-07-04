//
//  TNLRequestConfiguration_Project.h
//  TwitterNetworkLayer
//
//  Created on 8/13/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLParameterCollection.h"
#import "TNLRequestConfiguration.h"

/*
 * NOTE: this header is private to TNL
 */

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSURLCache * __nullable
TNLUnwrappedURLCache(NSURLCache * __nullable cache);

FOUNDATION_EXTERN NSURLCredentialStorage * __nullable
TNLUnwrappedURLCredentialStorage(NSURLCredentialStorage * __nullable storage);

FOUNDATION_EXTERN NSHTTPCookieStorage * __nullable
TNLUnwrappedCookieStorage(NSHTTPCookieStorage * __nullable storage);

FOUNDATION_EXTERN TNLMutableParameterCollection * __nullable
TNLMutableParametersFromRequestConfiguration(TNLRequestConfiguration *config,
                                             NSURLCache * __nullable canonicalCache,
                                             NSURLCredentialStorage * __nullable canonicalCredentialStorage,
                                             NSHTTPCookieStorage * __nullable canonicalCookieStorage); // always omits execution mode

FOUNDATION_EXTERN void
TNLMutableParametersStripURLCacheAndURLCredentialStorageAndCookieStorage(TNLMutableParameterCollection *params);

FOUNDATION_EXTERN NSArray<Class> * __nullable
TNLProtocolClassesForProtocolOptions(TNLRequestProtocolOptions options);

FOUNDATION_EXTERN TNLRequestProtocolOptions
TNLProtocolOptionsForProtocolClasses(NSArray<Class> * __nullable protocols);

FOUNDATION_EXTERN void
TNLRequestConfigurationAssociateWithRequest(TNLRequestConfiguration *config, NSURLRequest *request);

FOUNDATION_EXTERN TNLRequestConfiguration * __nullable
TNLRequestConfigurationGetAssociatedWithRequest(NSURLRequest *request);

FOUNDATION_EXTERN NSURLCache *TNLGetURLCacheDemuxProxy(void);
FOUNDATION_EXTERN NSURLCredentialStorage *TNLGetURLCredentialStorageDemuxProxy(void);
FOUNDATION_EXTERN NSHTTPCookieStorage *TNLGetHTTPCookieStorageDemuxProxy(void);

@interface TNLRequestConfiguration (Project)

+ (nullable instancetype)parseConfigurationFromIdentifier:(nullable NSString *)identifier;
+ (instancetype)configurationFromParameters:(nullable TNLParameterCollection *)params
                              executionMode:(TNLRequestExecutionMode)mode
                                    version:(nullable NSString *)tnlVersion;
- (void)applyDefaultTimeouts;

@end

NS_ASSUME_NONNULL_END

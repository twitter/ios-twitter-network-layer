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

// Keys for TNL

FOUNDATION_EXTERN NSString * const TNLTwitterNetworkLayerURLScheme;

// Key for TNLRequestConfiguration

FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyRedirectPolicy;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyResponseDataConsumptionMode;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyProtocolOptions;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyIdleTimeout;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyAttemptTimeout;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyOperationTimeout;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyDeferrableInterval;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyCookieAcceptPolicy;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyCachePolicy;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyNetworkServiceType;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyAllowsCellularAccess;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyDiscrectionary;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyShouldLaunchAppForBackgroundEvents;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyShouldSetCookies;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyCookieStorage;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyURLCredentialStorage;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyURLCache;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeySharedContainerIdentifier;
FOUNDATION_EXTERN NSString * const TNLRequestConfigurationPropertyKeyMultipathServiceType;

@interface TNLRequestConfiguration (Project)

+ (nullable instancetype)parseConfigurationFromIdentifier:(nullable NSString *)identifier;
+ (instancetype)configurationFromParameters:(nullable TNLParameterCollection *)params
                              executionMode:(TNLRequestExecutionMode)mode
                                    version:(nullable NSString *)tnlVersion;
- (void)applyDefaultTimeouts;

@end

NS_ASSUME_NONNULL_END

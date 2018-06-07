//
//  NSURLSessionConfiguration+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 8/12/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLURLSessionManager.h"

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_IPHONE
#define TNL_URL_SESSION_CONFIG_LINKS_DEPRECATED_INIT_WITH_IDENTIFIER_METHOD (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0)
#elif TARGET_OS_MAC
#define TNL_URL_SESSION_CONFIG_LINKS_DEPRECATED_INIT_WITH_IDENTIFIER_METHOD (__MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_10)
#else
#define TNL_URL_SESSION_CONFIG_LINKS_DEPRECATED_INIT_WITH_IDENTIFIER_METHOD (0)
#endif

static BOOL _NSURLSessionConfigurationHasUncementedPersistenceValues(void);

@implementation NSURLSessionConfiguration (TNLAdditions)

+ (BOOL)tnl_supportsSharedContainerIdentifier
{
    static BOOL sSupported;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Get the default config and check if it responds
        NSURLSessionConfiguration *defaultConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        sSupported = [defaultConfig respondsToSelector:@selector(setSharedContainerIdentifier:)];
    });
    return sSupported;
}

+ (BOOL)tnl_URLSessionCanReceiveResponseViaDelegate
{
    static BOOL sBugExists;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        const NSOperatingSystemVersion OSVersion = [processInfo respondsToSelector:@selector(operatingSystemVersion)] ? processInfo.operatingSystemVersion : (NSOperatingSystemVersion){ 0, 0, 0 };

#if TARGET_OS_IPHONE
        sBugExists = (OSVersion.majorVersion == 8);
#elif TARGET_OS_OSX
        sBugExists = (OSVersion.majorVersion == 10 && OSVersion.minorVersion == 10);
#else
        (void)OSVersion;
        sBugExists = NO;
#endif

    });

    return !sBugExists;
}

+ (BOOL)tnl_URLSessionCanUseTaskTransactionMetrics
{
    static BOOL sTaskMetricsAvailable = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        if (![processInfo respondsToSelector:@selector(operatingSystemVersion)]) {
            // version is too low
            return;
        }

        const NSOperatingSystemVersion OSVersion = processInfo.operatingSystemVersion;
#if TARGET_OS_IPHONE
        if (OSVersion.majorVersion < 10) {
            // task metrics don't exist
        } else if (OSVersion.majorVersion == 10) {
            // iOS 10.0.X and iOS 10.1.X have a crashing bug that crashes 1 million times a day
            // iOS 10.2+ has a different crasher, 5 thousand per day
        } else if (OSVersion.majorVersion == 11) {
            // fixed in iOS 11 ...
            if (OSVersion.minorVersion == 0 && OSVersion.patchVersion == 0) {
                // ... but some betas still had the crash, so let's require the first patch revision
            } else {
                // definitely fixed on 11.0.1 and up
                sTaskMetricsAvailable = YES;
            }
        } else {
            // newer releases
            sTaskMetricsAvailable = YES;
        }
#elif TARGET_OS_OSX
        if (OSVersion.majorVersion < 10) {
            // task metrics don't exist
        } else if (OSVersion.majorVersion == 10) {
            if (OSVersion.minorVersion < 12) {
                // task metrics don't exist
            } else if (OSVersion.minorVersion == 12) {
                // macOS 10.12.0 and macOS 10.12.1 has a bad crasher
                // 10.12.2+ has a different (less severe) crasher
            } else {
                // finally fixed in macOS 10.13 GM
                sTaskMetricsAvailable = YES;
            }
        } else {
            // macOS 11 (if this every happens)
            sTaskMetricsAvailable = YES;
        }
#else
        // Unexpected target, assume it cannot be used
        (void)OSVersion;
        sTaskMetricsAvailable = NO;
#endif

    });

    return sTaskMetricsAvailable;
}

+ (void)tnl_cementConfiguration:(NSURLSessionConfiguration *)config
{
    if (config && _NSURLSessionConfigurationHasUncementedPersistenceValues()) {
        // On iOS 7, Apple made a design choice with the URLCache, URLCredentialStorage and HTTPCookieStorage properties
        // Those getters would lazily load their objects but would not populate the ivar.
        // This meant that multiple calls to the same getter would yield different objects.
        // When the setter is called, however, the ivar would be persistently set (including with nil).
        // On iOS 8, Apple (thankfully) relented on this design choice and lazy loading will now populate the ivar.
        config.URLCache = config.URLCache;
        config.URLCredentialStorage = config.URLCredentialStorage;
        config.HTTPCookieStorage = config.HTTPCookieStorage;
    }
}

+ (instancetype)tnl_backgroundSessionConfigurationWithIdentifier:(NSString *)identifier
{
#if TNL_URL_SESSION_CONFIG_LINKS_DEPRECATED_INIT_WITH_IDENTIFIER_METHOD
    if ([self tnl_supportsSharedContainerIdentifier] /* proxy for support of new constructor */) {
        return [[self class] backgroundSessionConfigurationWithIdentifier:identifier];
    } else {
        return [[self class] backgroundSessionConfiguration:identifier];
    }
#else
    return [[self class] backgroundSessionConfigurationWithIdentifier:identifier];
#endif
}

+ (BOOL)tnl_URLSessionSupportsDecodingBrotliContentEncoding
{
    static BOOL sBrotliSupported = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        if (![processInfo respondsToSelector:@selector(operatingSystemVersion)]) {
            // version is too low
            return;
        }

        const NSOperatingSystemVersion OSVersion = processInfo.operatingSystemVersion;
        (void)OSVersion;
#if TARGET_OS_IPHONE
    #if defined(__IPHONE_11_0) && (__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_11_0)
        if (OSVersion.majorVersion >= 11) {
            sBrotliSupported = YES;
        }
    #endif
#elif TARGET_OS_TV
    #if defined(__TVOS_11_0) && (__TV_OS_VERSION_MAX_ALLOWED >= __TVOS_11_0)
        if (OSVersion.majorVersion >= 11) {
            sBrotliSupported = YES;
        }
    #endif
#elif TARGET_OS_WATCH
    #if defined(__WATCHOS_4_0) && (__WATCH_OS_VERSION_MAX_ALLOWED >= __WATCHOS_4_0)
        if (OSVersion.majorVersion >= 4) {
            sBrotliSupported = YES;
        }
    #endif
#elif TARGET_OS_OSX
    #if defined(__MAC_10_13) && (__MAC_OS_X_VERSION_MAX_ALLOWED >= __MAC_10_13)
        if (OSVersion.majorVersion > 10) {
            // Assume post "10" will have brotli
            sBrotliSupported = YES;
        } else if (OSVersion.majorVersion == 10 && OSVersion.minorVersion >= 13) {
            sBrotliSupported = YES;
        }
    #endif
#else
        // Unexpected target, assume it cannot be used
        sBrotliSupported = NO;
#endif

    });

    return sBrotliSupported;
}

@end

@implementation NSURLSessionConfiguration (TaggedIdentifier)

+ (instancetype)tnl_backgroundSessionConfigurationWithTaggedIdentifier:(NSString *)identifier
{
    NSURLSessionConfiguration *config = [self tnl_backgroundSessionConfigurationWithIdentifier:identifier];
    TNLRequestConfiguration *configParams = [TNLRequestConfiguration parseConfigurationFromIdentifier:identifier];
    if (configParams) {
        [configParams applySettingsToSessionConfiguration:config];
    }
    return config;
}

@end

static BOOL _NSURLSessionConfigurationHasUncementedPersistenceValues()
{
    // iOS 7 has this issue, which we'll use the container identifier for
    // (to also match on other platforms like macOS)
    return ![NSURLSessionConfiguration tnl_supportsSharedContainerIdentifier];
}

NS_ASSUME_NONNULL_END

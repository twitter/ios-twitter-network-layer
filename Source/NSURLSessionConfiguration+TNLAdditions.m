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

@implementation NSURLSessionConfiguration (TNLAdditions)

+ (BOOL)tnl_URLSessionCanReceiveResponseViaDelegate
{
    static BOOL sBugExists;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        if (tnl_available_ios_9) {
            // ok
        } else {
            // iOS 8 only has this bug
            sBugExists = YES;
        }

    });

    return !sBugExists;
}

+ (BOOL)tnl_URLSessionCanUseTaskTransactionMetrics
{
    static BOOL sTaskMetricsAvailable = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        if (tnl_available_ios_10) {
            // task metrics added as an API in iOS 10

            if (tnl_available_ios_11) {
                // Crashers of iOS 10 continue into iOS 11 betas
                // Cannot differentiate iOS 11.0.0 and iOS 11 betas
                // So...
                //   On iOS 11.0.1, consider fixed
                //   On iOS 11.0.0, consider bug present
                //   On non-iOS targets, just presume non-beta and consider fixed
#if TARGET_OS_IOS
                if (@available(iOS 11.0.1, *)) {
                    // definitely fixed on iOS 11.0.1
                    sTaskMetricsAvailable = YES;
                }
#else
                // non-iOS, consider fixed
                sTaskMetricsAvailable = YES;
#endif
            } else {
                // task metrics exist but have crashes on iOS 10.X
                // iOS 10.0.X and iOS 10.1.X have a crashing bug that crashes 1 million times a day
                // iOS 10.2+ has a different crasher, 5 thousand per day
            }
        }

    });

    return sTaskMetricsAvailable;
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

        // Brotli support requires 2 things:
        // - Running OS version of iOS 11 (or equivalent platform version) or greater
        //   AND
        // - Target SDK at compile time of iOS 11 (or equivalent platform version) or greater

        const NSOperatingSystemVersion OSVersion = processInfo.operatingSystemVersion;
        (void)OSVersion;
#if TARGET_OS_IOS
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
    NSURLSessionConfiguration *config = [self backgroundSessionConfigurationWithIdentifier:identifier];
    TNLRequestConfiguration *configParams = [TNLRequestConfiguration parseConfigurationFromIdentifier:identifier];
    if (configParams) {
        [configParams applySettingsToSessionConfiguration:config];
    }
    return config;
}

@end

NS_ASSUME_NONNULL_END

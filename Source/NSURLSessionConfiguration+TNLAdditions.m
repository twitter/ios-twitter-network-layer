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

        // Brotli support requires 2 things:
        // - Running OS version of iOS 11 (or equivalent platform version) or greater
        //   AND
        // - Target SDK at compile time of iOS 11 (or equivalent platform version) or greater

#if TARGET_SDK_SUPPORTS_BROTLI
        if (tnl_available_ios_11) {
            sBrotliSupported = YES;
        }
#endif

    });

    return sBrotliSupported;
}

- (void)tnl_insertProtocolClasses:(nullable NSArray<Class> *)additionalClasses
{
    if (additionalClasses.count == 0) {
        return;
    }

    // get the default protocol classes
    NSMutableArray<Class> *protocolClasses = [NSMutableArray arrayWithArray:self.protocolClasses];

    // get the index of the first "NS" protocol
    NSUInteger index = 0;
    for (index = 0; index < protocolClasses.count; index++) {
        NSString *className = NSStringFromClass((Class)protocolClasses[index]);
        if ([className hasPrefix:@"_NS"] || [className hasPrefix:@"NS"]) {
            break;
        }
    }

    // insert the additional protocols BEFORE any NS protocols
    /*
     We want to do this because protocols are executed in order.
     If insert at the end, the Apple encoders will surely handle our requests and render the
     added protocol useless.
     If inserted at the beginning, other protocols that could have been added (like OHHTTPStubs)
     would end up being skipped -- and app level overrides should retain higher priority.
     So, instead, we will skip all protocols until we hit an Apple protocol (NS prefixed).
     */
    for (Class protocol in additionalClasses) {
        TNLAssert(index <= protocolClasses.count);
        [protocolClasses insertObject:protocol atIndex:index++];
    }

    // update the protocol
    self.protocolClasses = protocolClasses;
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

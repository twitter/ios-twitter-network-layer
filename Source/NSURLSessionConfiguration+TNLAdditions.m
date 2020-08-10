//
//  NSURLSessionConfiguration+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 8/12/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLURLSessionManager.h"

NS_ASSUME_NONNULL_BEGIN

static struct {
    BOOL URLSessionCanUseTaskTransactionMetrics:1;
    BOOL URLSessionSupportsDecodingBrotliContentEncoding:1;
    BOOL URLSessionCanUseWaitsForConnectivity:1;
} sFlags;

static void _EnsureFlags(void);
static void _EnsureFlags()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        memset(&sFlags, 0, sizeof(sFlags)); // clear the flags before we set them

        /// URLSessionCanUseTaskTransactionMetrics

        // task metrics added as an API in iOS 10
        {
            if (tnl_available_ios_11) {

                // The crashers of iOS 10 continue into iOS 11 betas.
                // The crash was fixed in iOS 11.0.0 GM.
                // Since we cannot differentiate GM vs earlier beta, there can be crashing...
                // ...but those betas are old enough now to not need special consideration.

                // Consider fixed on iOS 11+
                sFlags.URLSessionCanUseTaskTransactionMetrics = YES;

            } else {
                // task metrics exist but have crashes on iOS 10.X
                // iOS 10.0.X and iOS 10.1.X have a crashing bug that crashes 1 million times a day
                // iOS 10.2+ has a different crasher, 5 thousand per day
            }
        }

        /// URLSessionSupportsDecodingBrotliContentEncoding

        // Brotli support requires 2 things:
        // - Running OS version of iOS 11 (or equivalent platform version) or greater
        //   AND
        // - Target SDK at compile time of iOS 11 (or equivalent platform version) or greater

#if TARGET_SDK_SUPPORTS_BROTLI
        if (tnl_available_ios_11) {
            sFlags.URLSessionSupportsDecodingBrotliContentEncoding = YES;
        }
#endif

        /// URLSessionCanUseWaitsForConnectivity

        if (tnl_available_ios_11) {

            // added iOS 11
            sFlags.URLSessionCanUseWaitsForConnectivity = YES;

            if (tnl_available_ios_13) {

                // regressed iOS 13.0
                sFlags.URLSessionCanUseWaitsForConnectivity = NO;

                if (@available(iOS 13.1, tvOS 13.1, macOS 10.15.0, watchOS 6.1, *)) {

                    // fixed iOS 13.1 beta 1
                    // fixed macOS 10.15.0 beta 7
                    sFlags.URLSessionCanUseWaitsForConnectivity = YES;

                }
            }
        }
    });
}

@implementation NSURLSessionConfiguration (TNLAdditions)

+ (BOOL)tnl_URLSessionCanUseTaskTransactionMetrics
{
    _EnsureFlags();
    return sFlags.URLSessionCanUseTaskTransactionMetrics;
}

+ (BOOL)tnl_URLSessionSupportsDecodingBrotliContentEncoding
{
    _EnsureFlags();
    return sFlags.URLSessionSupportsDecodingBrotliContentEncoding;
}

+ (BOOL)tnl_URLSessionCanUseWaitsForConnectivity
{
    _EnsureFlags();
    return sFlags.URLSessionCanUseWaitsForConnectivity;
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

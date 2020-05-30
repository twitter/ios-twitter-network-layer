//
//  TNLMutableRequestConfiguration+TNLCLI.m
//  tnlcli
//
//  Created on 9/17/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

#import "TNLCLIError.h"
#import "TNLCLIPrint.h"
#import "TNLCLIUtils.h"
#import "TNLMutableRequestConfiguration+TNLCLI.h"


@implementation TNLMutableRequestConfiguration (TNLCLI)

+ (instancetype)tnlcli_configurationWithFile:(NSString *)filePath error:(NSError * _Nullable __autoreleasing *)errorOut
{
    @autoreleasepool {
        NSError *error;
        NSDictionary<NSString *, NSString *> *d;
        NSData *jsonData = [NSData dataWithContentsOfFile:filePath
                                                  options:0
                                                    error:&error];
        if (jsonData) {
            d = [NSJSONSerialization JSONObjectWithData:jsonData
                                                options:0
                                                  error:&error];
            if (d) {
                if ([d isKindOfClass:[NSDictionary class]]) {
                    if (d.count) {
                        __block BOOL allStrings = YES;
                        [d enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
                            if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSString class]]) {
                                allStrings = NO;
                                *stop = YES;
                            }
                        }];
                        if (!allStrings) {
                            d = nil;
                        }
                    }
                } else {
                    d = nil;
                }
            }
        }

        if (!error && !d) {
            error = TNLCLICreateError(TNLCLIErrorInvalidRequestConfigurationFileFormat, @{ @"file" : filePath });
        }

        if (errorOut) {
            *errorOut = error;
        }
        if (error) {
            return nil;
        }

        return [self tnlcli_configurationWithDictionary:d];
    }
}

+ (instancetype)tnlcli_configurationWithDictionary:(NSDictionary<NSString *,NSString *> *)d
{
    TNLMutableRequestConfiguration *config = [[self alloc] init];
    [d enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        (void)[config tnlcli_applySettingWithName:key value:obj];
    }];
    return config;
}

- (BOOL)tnlcli_applySettingWithName:(NSString *)name value:(NSString *)value
{
#define BOOL_SETTING(setting) \
do { \
    if ([name isEqualToString: @"" #setting ]) { \
        NSNumber *number = TNLCLIBoolNumberValueFromString(value); \
        if (number) { \
            self. setting = number.boolValue; \
            return YES; \
        } \
        TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' should be an BOOL for a `TNLRequestConfiguration`, but '%@' was provided", name, value]); \
        return NO; \
    } \
} while (0)

#define NUMBER_SETTING(setting, accessor) \
do { \
    if ([name isEqualToString: @"" #setting ]) { \
        NSNumber *number = TNLCLINumberValueFromString(value); \
        if (number) { \
            self. setting = [number accessor##Value]; \
            return YES; \
        } \
        TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' should be a " #accessor " for `TNLRequestConfiguration`, but '%@' was provided", name, value]); \
        return NO; \
    } \
} while (0)

#define STRING_SETTING(setting) \
do { \
    if ([name isEqualToString: @"" #setting ]) { \
        self. setting = value; \
        return YES; \
    } \
} while (0)


    /// BOOL settings

    BOOL_SETTING(contributeToExecutingNetworkConnectionsCount);
    BOOL_SETTING(skipHostSanitization);
    BOOL_SETTING(shouldSetCookies);
    BOOL_SETTING(allowsCellularAccess);
    BOOL_SETTING(discretionary);
    BOOL_SETTING(shouldUseExtendedBackgroundIdleMode);
    BOOL_SETTING(shouldLaunchAppForBackgroundEvents);


    /// Double settings

    NUMBER_SETTING(idleTimeout, double);
    NUMBER_SETTING(attemptTimeout, double);
    NUMBER_SETTING(operationTimeout, double);
    NUMBER_SETTING(deferrableInterval, double);


    /// Integer settings

    NUMBER_SETTING(executionMode, integer);
    NUMBER_SETTING(redirectPolicy, integer);
    NUMBER_SETTING(responseDataConsumptionMode, integer);
    NUMBER_SETTING(protocolOptions, integer);
    NUMBER_SETTING(connectivityOptions, integer);
    NUMBER_SETTING(responseComputeHashAlgorithm, integer);
    // NUMBER_SETTING(multipathServiceType, integer); -- unavailable on Mac


    /// Unsigned Integer settings

    NUMBER_SETTING(cachePolicy, unsignedInteger);
    NUMBER_SETTING(cookieAcceptPolicy, unsignedInteger);
    NUMBER_SETTING(networkServiceType, unsignedInteger);


    /// String settings

    STRING_SETTING(sharedContainerIdentifier);


    /// Unsupported from key-value-pair settings (aka TODO)

    //    @property id<TNLRequestRetryPolicyProvider> retryPolicyProvider;
    //    @property id<TNLContentEncoder> contentEncoder;
    //    @property NSArray<id<TNLContentDecoder>> *additionalContentDecoders;
    //    @property NSURLCredentialStorage *URLCredentialStorage;
    //    @property NSURLCache *URLCache;
    //    @property NSHTTPCookieStorage *cookieStorage;

    return NO;

#undef BOOL_SETTING
#undef NUMBER_SETTING
#undef STRING_SETTING
}

@end

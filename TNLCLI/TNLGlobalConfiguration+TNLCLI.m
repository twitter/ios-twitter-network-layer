//
//  TNLGlobalConfiguration+TNLCLI.m
//  tnlcli
//
//  Created on 9/17/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

#import "TNLCLIPrint.h"
#import "TNLCLIUtils.h"
#import "TNLGlobalConfiguration+TNLCLI.h"

@implementation TNLGlobalConfiguration (TNLCLI)

- (BOOL)tnlcli_applySettingWithName:(NSString *)name value:(NSString *)value
{
    if ([name isEqualToString:@"idleTimeoutMode"]) {
        NSNumber *number = TNLCLINumberValueFromString(value);
        if (number) {
            self.idleTimeoutMode = number.integerValue;
            return YES;
        } else {
            TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' should be an integer value matching the 'TNLGlobalConfigurationIdleTimeoutMode' enumeration for global configuration, but '%@' was provided", name, value]);
        }
    } else if ([name isEqualToString:@"timeoutIntervalBetweenDataTransfer"]) {
        NSNumber *number = TNLCLINumberValueFromString(value);
        if (number) {
            self.timeoutIntervalBetweenDataTransfer = number.doubleValue;
            return YES;
        } else {
            TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' should be a time interval in seconds as double for global configuration, but '%@' was provided", name, value]);
        }
    } else {
        TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' is not a recognized global configuration setting, ignoring it.", name]);
    }

    return NO;
}

@end

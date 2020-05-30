//
//  TNLCLIError.m
//  TNLCLI
//
//  Created on 9/11/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLCLIError.h"

NSString * const TNLCLIErrorDomain = @"tnlcli.error";

NSError *TNLCLICreateError(TNLCLIError code, id __nullable userInfoDictionaryOrDescriptionString)
{
    NSDictionary *userInfo = nil;
    if ([userInfoDictionaryOrDescriptionString isKindOfClass:[NSDictionary class]]) {
        userInfo = userInfoDictionaryOrDescriptionString;
    } else if ([userInfoDictionaryOrDescriptionString isKindOfClass:[NSString class]]) {
        userInfo = @{
                        NSDebugDescriptionErrorKey : [userInfoDictionaryOrDescriptionString copy]
                    };
    }

    return [NSError errorWithDomain:TNLCLIErrorDomain
                               code:code
                           userInfo:userInfo];
}

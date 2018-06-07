//
//  NSURLRequest+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 11/9/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "NSURL+TNLAdditions.h"
#import "NSURLRequest+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLError.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSURLRequest (TNLAdditions)

- (nullable NSString *)tnl_hostName
{
    return [self valueForHTTPHeaderField:@"Host"] ?: self.URL.host;
}

@end

@implementation NSMutableURLRequest (TNLAdditions)

- (TNLHostReplacementResult)tnl_replaceURLHost:(NSString *)newHost
                                      behavior:(TNLHostSanitizerBehavior)behavior
                                         error:(out NSError * __autoreleasing __nullable * __nullable)error
{
    __block NSError *returnError = nil;
    tnl_defer(^{
        if (returnError && error) {
            *error = returnError;
        }
    });

    NSString *oldHost = self.URL.host;
    if (TNLHostSanitizerBehaviorBlock == behavior) {

        returnError = TNLErrorCreateWithCodeAndUserInfo(TNLErrorCodeGlobalHostWasBlocked, (oldHost) ? @{ TNLErrorHostKey : oldHost } : nil);
        return TNLHostReplacementResultFail;

    } else if (TNLHostSanitizerBehaviorIsModification(behavior)) {

        if (newHost.length == 0) {
            returnError = TNLErrorCreateWithCode(TNLErrorCodeOtherHostCannotBeEmpty);
            return TNLHostReplacementResultFail;
        }

        if ([oldHost isEqualToString:newHost]) {
            return TNLHostReplacementResultNoop;
        }

        self.URL = [self.URL tnl_URLByReplacingHost:newHost];
        if (TNLHostSanitizerBehaviorChange == behavior && ![self valueForHTTPHeaderField:@"Host"]) {
            // update the "Host"
            [self setValue:oldHost forHTTPHeaderField:@"Host"];
        }

        return TNLHostReplacementResultSuccess;

    }

    return TNLHostReplacementResultNoop;
}

@end

NS_ASSUME_NONNULL_END

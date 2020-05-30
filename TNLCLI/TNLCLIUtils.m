//
//  TNLCLIUtils.m
//  tnlcli
//
//  Created on 9/17/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLCLIUtils.h"

BOOL TNLCLIParseColonSeparatedKeyValuePair(NSString *str, NSString ** keyOut, NSString ** valueOut)
{
    NSString *key, *value;
    const NSUInteger indexOfColon = [str rangeOfString:@":"].location;
    if (indexOfColon != NSNotFound) {
        @autoreleasepool {
            key = [[str substringToIndex:indexOfColon] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            value = [[str substringFromIndex:indexOfColon+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }

    if (keyOut) {
        *keyOut = key;
    }
    if (valueOut) {
        *valueOut = value;
    }
    return (key && value);
}

NSNumber *TNLCLINumberValueFromString(NSString *value)
{
    NSScanner *scanner = [NSScanner scannerWithString:value];
    double num;
    if ([scanner scanDouble:&num] && scanner.atEnd) {
        return @(num);
    }
    return nil;
}

NSNumber *TNLCLIBoolNumberValueFromString(NSString *value)
{
    value = value.lowercaseString;

    static NSSet<NSString *> *sTrueStrings;
    static NSSet<NSString *> *sFalseStrings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTrueStrings = [NSSet setWithObjects:@"true", @"yes", @"1", nil];
        sFalseStrings = [NSSet setWithObjects:@"false", @"no", @"0", nil];
    });

    if ([sTrueStrings containsObject:value]) {
        return @YES;
    }
    if ([sFalseStrings containsObject:value]) {
        return @NO;
    }
    return nil;
}


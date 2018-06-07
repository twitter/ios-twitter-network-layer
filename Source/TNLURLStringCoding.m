//
//  TNLURLStringCoding.m
//  TwitterNetworkLayer
//
//  Created on 7/28/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLURLCoding.h"

NS_ASSUME_NONNULL_BEGIN

static const char kHexDigits[] = "0123456789ABCDEF";

NSString * __nullable TNLURLEncodeString(NSString * __nullable string)
{
    if (0 == string.length) {
        return @"";
    }

    const char *stringAsUTF8 = [string UTF8String];
    if (stringAsUTF8 == NULL) {
        NSMutableString *byteString = [[NSMutableString alloc] init];
        for (NSUInteger i = 0; i < string.length; i++) {
            unichar uchar = [string characterAtIndex:i];
            [byteString appendFormat:@"%02X ", uchar];
        }
        TNLLogError(@"No UTF8String for NSString:\n%@", byteString);
        return nil;
    }

    NSUInteger encodedLength = 0;
    BOOL needsEncoding = NO;
    for (const char *c = stringAsUTF8; *c; c++) {
        switch (*c) {
            case '0' ... '9':
            case 'A' ... 'Z':
            case 'a' ... 'z':
            case '-':
            case '.':
            case '_':
            case '~':
                encodedLength++;
                break;
            default:
                encodedLength += 3;
                needsEncoding = YES;
                break;
        }
    }
    if (!needsEncoding) {
        return string;
    }

    char *encodedBytes = malloc(encodedLength);
    if (NULL == encodedBytes) {
        TNLLogError(@"Out of memory");
        return nil;
    }

    char *outPtr = encodedBytes;
    for (const unsigned char *c = (const unsigned char *)stringAsUTF8; *c; c++) {
        switch (*c) {
            case '0' ... '9':
            case 'A' ... 'Z':
            case 'a' ... 'z':
            case '-':
            case '.':
            case '_':
            case '~':
                *outPtr++ = (char)*c;
                break;
            default:
                *outPtr++ = '%';
                *outPtr++ = kHexDigits[(*c>>4)&0xf];
                *outPtr++ = kHexDigits[*c&0xf];
                break;
        }
    }

    NSString *encodedString = [[NSString alloc] initWithBytesNoCopy:encodedBytes length:encodedLength encoding:NSASCIIStringEncoding freeWhenDone:YES];
    if (encodedString == nil) {
        TNLLogError(@"Can't create encodedString from '%@'", string);
        free(encodedBytes);
    }
    return encodedString;
}

NSString * __nullable TNLURLDecodeString(NSString * __nullable string, BOOL replacePlussesWithSpaces)
{
    NSString *s = string;
    // replace the '+' first since if the '+' is encoded we want to preserve its value
    if (replacePlussesWithSpaces) {
        s = [s stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    }

    // the deprecated [s stringByReplacingPercentExcapesUsingEncoding:NSUTF8StringEncoding]
    // used to return @"" for @"" .  the replacement method returns nil.
    //
    // by checking length, we preserve the old behavior for this caller in case anything depended upon it.
    return s.length ? [s stringByRemovingPercentEncoding] : s;
}

NS_ASSUME_NONNULL_END


//
//  TNLHTTP.m
//  TwitterNetworkLayer
//
//  Created on 6/9/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLHTTP.h"

NS_ASSUME_NONNULL_BEGIN

static const size_t kMaxTimeFormattedStringLength = 80;

typedef struct _TNLHTTPTimeFormatInfo {
    const char *readFormat;
    const char *writeFormat;
    BOOL usesHasTimezoneInfo;
} TNLHTTPTimeFormatInfo;

static TNLHTTPTimeFormatInfo kTimeFormatInfos[] =
{
    { NULL, NULL, NO },
    { "%a, %d %b %Y %H:%M:%S %Z", "%a, %d %b %Y %H:%M:%S GMT", YES },    // TNLHTTPDateFormatRFC822
    { "%A, %d-%b-%y %H:%M:%S %Z", "%A, %d-%b-%y %H:%M:%S GMT", YES },    // TNLHTTPDateFormatRFC850
    { "%a %b %e %H:%M:%S %Y", "%a %b %e %H:%M:%S %Y", NO },              // TNLHTTPDateFormatANSIC
    { "%a %b %d %H:%M:%S %z %Y", "%a %b %d %H:%M:%S %z %Y", YES },       // TNLHTTPDateFormatANSICExt
};

TNLStaticAssert((sizeof(kTimeFormatInfos) / sizeof(kTimeFormatInfos[0])) == 5, MISALIGNED_TIME_FORMAT_STRUCT);

NSString * const TNLHTTPContentTypeJPEGImage = @"image/jpeg";
NSString * const TNLHTTPContentTypeQuicktimeVideo = @"video/quicktime";
NSString * const TNLHTTPContentTypeJSON = @"application/json";
NSString * const TNLHTTPContentTypeTextPlain = @"text/plain";
NSString * const TNLHTTPContentTypeMultipartFormData = @"multipart/form-data";
NSString * const TNLHTTPContentTypeOctetStream = @"application/octet-stream";
NSString * const TNLHTTPContentTypeURLEncodedString = @"application/x-www-form-urlencoded";

static BOOL TNLHTTPContentTypeIsTextualInternal(NSString * __nonnull contentType)
{
    if ([contentType hasPrefix:@"text/"]) {
        return YES;
    }

    if ([contentType isEqualToString:TNLHTTPContentTypeURLEncodedString]) {
        return YES;
    }

    if ([contentType isEqualToString:TNLHTTPContentTypeJSON]) {
        return YES;
    }

    if ([contentType hasPrefix:@"application"]) {
        if ([contentType hasSuffix:@"/xml"]) {
            return YES;
        }
        if ([contentType hasSuffix:@"+xml"]) {
            return YES;
        }
    }

    return NO;
}

BOOL TNLHTTPContentTypeIsTextual(NSString * __nullable contentType)
{
    if (!contentType) {
        return NO;
    }

    // Is this a componentized mimetype? e.g. "application/json;charset=utf-8"
    NSArray<NSString *> *components = [contentType componentsSeparatedByString:@";"];
    if (components.count <= 1) {
        // nope, do the easy check
        return TNLHTTPContentTypeIsTextualInternal(contentType);
    }

    // It is componentized, get the content type and check it
    contentType = [components.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!TNLHTTPContentTypeIsTextualInternal(contentType)) {
        // content type is not textual
        return NO;
    }

    // Content type is textual, need to confirm the character set is acceptable (we restrict to utf-8 and ascii for simplicity)
    for (NSUInteger i = 1; i < components.count; i++) {
        NSString *extraInfo = components[i].lowercaseString;
        NSArray<NSString *> *extraComponents = [extraInfo componentsSeparatedByString:@"="];
        NSString *key = [extraComponents.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([key isEqualToString:@"charset"]) {
            // charset was provided, so check it and return if the character set is utf8/ascii
            NSString *value = [extraComponents.lastObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([value isEqualToString:@"utf-8"]) {
                return YES;
            } else if ([value isEqualToString:@"ascii"] || [value isEqualToString:@"us-ascii"]) {
                return YES;
            }

            return NO;
        }
    }

    // no charset provided, presume utf-8
    return YES;
}

NSString *TNLHTTPMethodToString(TNLHTTPMethod method)
{
#define METHOD_CASE(m) \
case TNLHTTPMethod##m : { return @"" #m ; }

    switch (method) {
            METHOD_CASE(OPTIONS)
            METHOD_CASE(GET)
            METHOD_CASE(HEAD)
            METHOD_CASE(POST)
            METHOD_CASE(PUT)
            METHOD_CASE(DELETE)
            METHOD_CASE(TRACE)
            METHOD_CASE(CONNECT)
        case TNLHTTPMethodUnknown:
            return nil;
    }

    TNLAssertNever();
    return nil;

#undef METHOD_CASE
}

TNLHTTPMethod TNLHTTPMethodFromString(NSString *methodString)
{
#define METHOD_CASE(m) \
if (methodString && [methodString caseInsensitiveCompare:@"" #m ] == NSOrderedSame) { /* TWITTER_STYLE_CASE_INSENSITIVE_COMPARE_NIL_PRECHECKED */ \
    return TNLHTTPMethod##m ; \
} else
#define METHOD_CASE_UNKNOWN \
{ return TNLHTTPMethodUnknown; }

    METHOD_CASE(OPTIONS)
    METHOD_CASE(GET)
    METHOD_CASE(HEAD)
    METHOD_CASE(POST)
    METHOD_CASE(PUT)
    METHOD_CASE(DELETE)
    METHOD_CASE(TRACE)
    METHOD_CASE(CONNECT)
    METHOD_CASE_UNKNOWN

#undef METHOD_CASE
}

NSDate * __nullable TNLHTTPDateFromString(NSString * __nullable string,
                                          TNLHTTPDateFormat * __nullable detectedFormat)
{
    NSDate *date = nil;
    TNLHTTPDateFormat format = TNLHTTPDateFormatUnknown;
    if (string) {
        struct tm parsedTime;
        const char *utf8String = [string UTF8String];

        for (format = (TNLHTTPDateFormatUnknown + 1); (size_t)format < (sizeof(kTimeFormatInfos) / sizeof(kTimeFormatInfos[0])); format++) {
            TNLHTTPTimeFormatInfo info = kTimeFormatInfos[format];
            bzero(&parsedTime, sizeof(parsedTime));
            if (info.readFormat != NULL && strptime(utf8String, info.readFormat, &parsedTime)) {
                const NSTimeInterval ti = (info.usesHasTimezoneInfo ? mktime(&parsedTime) : timegm(&parsedTime));
                date = [NSDate dateWithTimeIntervalSince1970:ti];
                if (date) {
                    break;
                }
            }
        }
    }

    if (detectedFormat) {
        *detectedFormat = (date != nil) ? format : TNLHTTPDateFormatUnknown;
    }

    return date;
}

NSString * __nullable TNLHTTPDateToString(NSDate * __nullable date,
                                          TNLHTTPDateFormat format)
{
    NSString *string = nil;
    if (date) {
        if (format == 0 || ((size_t)format >= (sizeof(kTimeFormatInfos) / sizeof(kTimeFormatInfos[0])))) {
            format = TNLHTTPDateFormatRFC822;
        }
        time_t timeRaw = (long)date.timeIntervalSince1970;
        struct tm timeStruct;
        char buffer[kMaxTimeFormattedStringLength];

        gmtime_r(&timeRaw, &timeStruct);
        size_t charCount = strftime(buffer, sizeof(buffer), kTimeFormatInfos[format].writeFormat, &timeStruct);
        if (0 != charCount) {
            string = [[NSString alloc] initWithCString:buffer
                                              encoding:NSASCIIStringEncoding];
        }
    }

    return string;
}

NS_ASSUME_NONNULL_END

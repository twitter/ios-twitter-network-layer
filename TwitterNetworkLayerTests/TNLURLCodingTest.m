//
//  TNLURLCodingTest.m
//  TwitterNetworkLayer
//
//  Created on 11/12/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSNumber+TNLURLCoding.h"
#import "TNLURLCoding.h"

@import XCTest;

@interface TNLURLCodingTest : XCTestCase

@end

@implementation TNLURLCodingTest

- (void)testURLEncodedString
{
    NSString *original = @"abc ~!@#$%^&*()+=[]{}|\\/,.<>;:'\"☃ 汉字/漢字";
    NSString *expected = @"abc%20~%21%40%23%24%25%5E%26%2A%28%29%2B%3D%5B%5D%7B%7D%7C%5C%2F%2C.%3C%3E%3B%3A%27%22%E2%98%83%20%E6%B1%89%E5%AD%97%2F%E6%BC%A2%E5%AD%97";

    NSString *encoded = TNLURLEncodeString(original);
    XCTAssertEqualObjects(encoded, expected, @"TNLURLEncodeString() doesn't match");
    NSString *decoded = TNLURLDecodeString(encoded, NO);
    XCTAssertEqualObjects(decoded, original);

    expected = [expected stringByReplacingOccurrencesOfString:@"%20" withString:@"+"];
    decoded = TNLURLDecodeString(expected, YES);
    XCTAssertEqualObjects(decoded, original);
}

- (void)testURLParameterParsing
{
    NSString *query = @"log%5B%5D=%7B%22foo%22%3A%22bar%22%7D";
    NSDictionary *dict = TNLURLDecodeDictionary(query, 0);
    XCTAssertEqualObjects(@"log[]", [[dict allKeys] objectAtIndex:0], @"Unescaped key not found");
    XCTAssertEqualObjects(@"{\"foo\":\"bar\"}", [dict objectForKey:@"log[]"], @"Unescaped value not found");
    NSString *reverse = TNLURLEncodeDictionary(dict, 0);
    XCTAssertEqualObjects(query, reverse);

    query = @"a=one&b=two&c=three&d=four&e=five&g";
    NSMutableDictionary *mDict = (id)TNLURLDecodeDictionary(query, TNLURLDecodingOptionOutputMutableDictionary);
    XCTAssertEqual(6UL, mDict.count);
    XCTAssertEqualObjects(@"", mDict[@"g"]);
    mDict[@"g"] = @"six";
    reverse = TNLURLEncodeDictionary(mDict, TNLURLEncodingOptionStableOrder);
    XCTAssertEqualObjects(reverse, [query stringByAppendingString:@"=six"]);
    reverse = TNLURLEncodeDictionary(mDict, 0);
    XCTAssertNotEqualObjects(reverse, [query stringByAppendingString:@"=six"]);

    query = @"a=3=11&b=10=2=1010=A";
    dict = TNLURLDecodeDictionary(query, 0);
    XCTAssertEqualObjects(@"3=11", dict[@"a"]);
    XCTAssertEqualObjects(@"10=2=1010=A", dict[@"b"]);

    query = @"a=1+1&b=1%2B1";
    dict = TNLURLDecodeDictionary(query, 0);
    XCTAssertEqualObjects(@"1 1", dict[@"a"]);
    XCTAssertEqualObjects(@"1+1", dict[@"b"]);
    dict = TNLURLDecodeDictionary(query, TNLURLDecodingOptionPreservePlusses);
    XCTAssertEqualObjects(@"1+1", dict[@"a"]);
    XCTAssertEqualObjects(@"1+1", dict[@"b"]);


    query = @"=empty&ok=not-empty";
    dict = TNLURLDecodeDictionary(query, 0);
    XCTAssertEqual((NSUInteger)1, (NSUInteger)dict.count);
    XCTAssertNil(dict[@""]);
    XCTAssertNotNil(dict[@"ok"]);

    mDict = [NSMutableDictionary dictionary];
    mDict[@""] = @"empty";
    mDict[@"ok"] = @"not-empty";
    query = TNLURLEncodeDictionary(mDict, 0);
    XCTAssertEqualObjects(query, @"ok=not-empty");
}

- (void)_runNumberCoding:(BOOL)testTiming
{
    NSArray<NSNumber *> *numbers = @[
        @((BOOL)YES),
        @((BOOL)NO),
        @((BOOL)7),

        @((uint8_t)0),
        @((uint8_t)UINT8_MAX),
        @((int8_t)INT8_MIN),
        @((int8_t)0),
        @((int8_t)INT8_MAX),

        @((uint16_t)0),
        @((uint16_t)UINT16_MAX),
        @((int16_t)INT16_MIN),
        @((int16_t)0),
        @((int16_t)INT16_MAX),

        @((uint32_t)0),
        @((uint32_t)UINT32_MAX),
        @((int32_t)INT32_MIN),
        @((int32_t)0),
        @((int32_t)INT32_MAX),

        @((uint64_t)0),
        @((uint64_t)UINT64_MAX),
        @((int64_t)INT64_MIN),
        @((int64_t)0),
        @((int64_t)INT64_MAX),

        @(FLT_MIN),
        @(0.f),
        @(FLT_MAX),
        @((float)M_PI),

        @(DBL_MIN),
        @(0.f),
        @(DBL_MAX),
        @(M_PI),
    ];

    NSTimeInterval nsDuration, tnlDuration;
    const NSUInteger iterations = 20000;
#define PRINT_NUMBERS 0

    {
#if PRINT_NUMBERS
        BOOL didPrint = NO;
#endif
        const CFAbsoluteTime nsStart = CFAbsoluteTimeGetCurrent();
        for (NSUInteger i = 0; i < iterations; i++) {
            for (NSNumber *number in numbers) {
                NSString *value = [number stringValue];
#if PRINT_NUMBERS
                if (!didPrint) {
                    NSLog(@"%@", value);
                }
#endif
                (void)value;
            }
#if PRINT_NUMBERS
            didPrint = YES;
#endif
        }
        const CFAbsoluteTime nsEnd = CFAbsoluteTimeGetCurrent();
        nsDuration = nsEnd - nsStart;
        NSLog(@"-[NSNumber stringValue] = %fs", nsDuration);
    }

    {
#if PRINT_NUMBERS
        BOOL didPrint = NO;
#endif
        const CFAbsoluteTime tnlStart = CFAbsoluteTimeGetCurrent();
        for (NSUInteger i = 0; i < iterations; i++) {
            for (NSNumber *number in numbers) {
                NSString *value = [number tnl_quickStringValue];
#if PRINT_NUMBERS
                if (!didPrint) {
                    NSLog(@"%@", value);
                }
#endif
                (void)value;
            }
#if PRINT_NUMBERS
            didPrint = YES;
#endif
        }
        const CFAbsoluteTime tnlEnd = CFAbsoluteTimeGetCurrent();
        tnlDuration = tnlEnd - tnlStart;
        NSLog(@"-[NSNumber tnl_quickStringValue] = %fs", tnlDuration);
    }

    if (testTiming) {
        XCTAssertLessThan(tnlDuration, nsDuration, @"-[NSNumber tnl_quickStringValue] ought to be faster than -[NSNumber stringValue]!");
    }
}

- (void)testNumberCoding
{
    [self _runNumberCoding:NO];
}

- (void)testNumberCodingSpeed
{
    [self _runNumberCoding:YES];
}

@end

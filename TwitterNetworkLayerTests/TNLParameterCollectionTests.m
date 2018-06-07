//
//  TNLParameterCollectionTests.m
//  TwitterNetworkLayer
//
//  Created on 10/27/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#include <objc/runtime.h>
#import "NSNumber+TNLURLCoding.h"
#import "TNL_Project.h"
#import "TNLParameterCollection.h"

@import XCTest;

#define PATH            @"http://www.something.com/some/path"
#define PARAMS_STRING   @";one=1&two=&three&snowman=%E2%98%83&emoji=%E2%9B%84%EF%B8%8F"
#define QUERY_STRING    @"?une=1&deux=&trois&char=%26&array_of_dictionaries=%5B%7B%22key1%22%3A%22value1%22%2C%22key2%22%3A2%7D%2C%20%7B%22key3%22%3Anull%7D%5D"
#define FRAGMENT_STRING @"#uno=1&dos=&tres&inner_url=http%3A%2F%2Fwww.something.com%2Fother%2Fpath%3Fextra%3Dinfo&z"

#define ARG_COUNT (5UL)

@interface TestBenignAssertionHandler : NSAssertionHandler
@property (nonatomic, readonly) NSUInteger assertCount;
@end

@interface InvalidString : NSProxy
@end

static BOOL sSupportCustomEncoding = NO;

static void TestSwizzle(Class cls, SEL originalSelector, SEL swizzledSelector)
{
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSelector);
    BOOL didAddMethod = class_addMethod(cls, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
    if (didAddMethod) {
        class_replaceMethod(cls, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

@interface NSURL (TestMethod)
- (NSString *)test_tnl_URLEncodableStringValue;
@end

@interface NSArray (TestMethod)
- (NSString *)test_tnl_URLEncodableStringValue;
@end

@implementation NSURL (TestMethod)
- (NSString *)test_tnl_URLEncodableStringValue
{
    if (!sSupportCustomEncoding) {
        return nil;
    }

    return [self absoluteString];
}
@end

@implementation NSArray (TestMethod)
- (NSString *)test_tnl_URLEncodableStringValue
{
    if (!sSupportCustomEncoding) {
        return nil;
    }

    NSMutableArray *subarray = [NSMutableArray arrayWithCapacity:self.count];
    for (id item in self) {
        NSString *val;
        if ([item isKindOfClass:[NSString class]]) {
            val = item;
        } else if ([item respondsToSelector:@selector(tnl_URLEncodableStringValue)]) {
            val = [item tnl_URLEncodableStringValue];
        } else if ([item respondsToSelector:@selector(stringValue)]) {
            val = [item stringValue];
        }
        if (val.length > 0) {
            [subarray addObject:val];
        }
    }
    [subarray sortUsingSelector:@selector(compare:)];
    return [subarray componentsJoinedByString:@","];
}
@end

@interface TNLParameterCollectionTests : XCTestCase <TNLURLEncodableObject>

@property (nonatomic, readonly) NSURL *pathURL;
@property (nonatomic, readonly) NSURL *paramURL;
@property (nonatomic, readonly) NSURL *queryURL;
@property (nonatomic, readonly) NSURL *fragmentURL;
@property (nonatomic, readonly) NSURL *allPartsURL;

- (void)executeTestWithParams:(TNLParameterCollection *)params options:(TNLURLEncodableDictionaryOptions)options supportingCustom:(BOOL)supportingCustom expected:(NSDictionary *)expected;

@end

@implementation TNLParameterCollectionTests

+ (void)setUpTearDown
{
    TestSwizzle([NSURL class], @selector(tnl_URLEncodableStringValue), @selector(test_tnl_URLEncodableStringValue));
    TestSwizzle([NSArray class], @selector(tnl_URLEncodableStringValue), @selector(test_tnl_URLEncodableStringValue));
}

+ (void)setUp
{
    [self setUpTearDown];
}

+ (void)tearDown
{
    [self setUpTearDown];
}

- (void)setUp
{
    [super setUp];

    _pathURL = [NSURL URLWithString:PATH];
    _paramURL = [NSURL URLWithString:PATH PARAMS_STRING];
    _queryURL = [NSURL URLWithString:PATH QUERY_STRING];
    _fragmentURL = [NSURL URLWithString:PATH FRAGMENT_STRING];
    _allPartsURL = [NSURL URLWithString:PATH PARAMS_STRING QUERY_STRING FRAGMENT_STRING];
}

- (void)runCategoryTest:(NSURL *)url expectParamCount:(NSUInteger)expectParamCount expectQueryCount:(NSUInteger)expectQueryCount expectFragmentCount:(NSUInteger)expectFragmentCount
{
    TNLParameterCollection *paramStringCollection = url.tnl_parameterStringCollection;
    TNLParameterCollection *queryCollection = url.tnl_queryCollection;
    TNLParameterCollection *fragmentCollection = url.tnl_fragmentCollection;

    XCTAssertEqual(paramStringCollection.count, expectParamCount);
    XCTAssertEqual(queryCollection.count, expectQueryCount);
    XCTAssertEqual(fragmentCollection.count, expectFragmentCount);

    if (expectParamCount) {
        XCTAssertEqualObjects(paramStringCollection[@"one"], @"1");
        XCTAssertEqualObjects(paramStringCollection[@"two"], @"");
        XCTAssertEqualObjects(paramStringCollection[@"three"], @"");

        XCTAssertEqualObjects(paramStringCollection[@"snowman"], @"☃");
        XCTAssertEqualObjects(paramStringCollection[@"emoji"], @"⛄️");

        NSDictionary *d = @{ @"one" : @"1", @"two" : @"", @"three" : @"", @"snowman" :  @"☃", @"emoji" : @"⛄️"};
        XCTAssertEqualObjects([paramStringCollection underlyingDictionaryValue], d);
        XCTAssertEqualObjects([paramStringCollection stableURLEncodedStringValue], @"emoji=%E2%9B%84%EF%B8%8F&one=1&snowman=%E2%98%83&three=&two=");
        XCTAssertEqualObjects([NSSet setWithArray:d.allKeys], [NSSet setWithArray:paramStringCollection.allKeys]);
    }

    if (expectQueryCount) {
        XCTAssertEqualObjects(queryCollection[@"une"], @"1");
        XCTAssertEqualObjects(queryCollection[@"deux"], @"");
        XCTAssertEqualObjects(queryCollection[@"trois"], @"");

        XCTAssertEqualObjects(queryCollection[@"char"], @"&");
        XCTAssertEqualObjects(queryCollection[@"array_of_dictionaries"], @"[{\"key1\":\"value1\",\"key2\":2}, {\"key3\":null}]");

        NSDictionary *d = @{ @"une" : @"1", @"deux" : @"", @"trois" : @"", @"char" : @"&", @"array_of_dictionaries" : @"[{\"key1\":\"value1\",\"key2\":2}, {\"key3\":null}]" };
        XCTAssertEqualObjects([queryCollection underlyingDictionaryValue], d);
        XCTAssertEqualObjects([queryCollection stableURLEncodedStringValue], @"array_of_dictionaries=%5B%7B%22key1%22%3A%22value1%22%2C%22key2%22%3A2%7D%2C%20%7B%22key3%22%3Anull%7D%5D&char=%26&deux=&trois=&une=1");
        XCTAssertEqualObjects([NSSet setWithArray:d.allKeys], [NSSet setWithArray:queryCollection.allKeys]);
    }

    if (expectFragmentCount) {
        XCTAssertEqualObjects(fragmentCollection[@"uno"], @"1");
        XCTAssertEqualObjects(fragmentCollection[@"dos"], @"");
        XCTAssertEqualObjects(fragmentCollection[@"tres"], @"");

        XCTAssertEqualObjects(fragmentCollection[@"inner_url"], @"http://www.something.com/other/path?extra=info");
        XCTAssertEqualObjects(fragmentCollection[@"z"], @"");

        NSDictionary *d = @{ @"uno" : @"1", @"dos" : @"", @"tres" : @"", @"inner_url" : @"http://www.something.com/other/path?extra=info", @"z" : @"" };
        XCTAssertEqualObjects([fragmentCollection underlyingDictionaryValue], d);
        XCTAssertEqualObjects([fragmentCollection stableURLEncodedStringValue], @"dos=&inner_url=http%3A%2F%2Fwww.something.com%2Fother%2Fpath%3Fextra%3Dinfo&tres=&uno=1&z=");
        XCTAssertEqualObjects([NSSet setWithArray:d.allKeys], [NSSet setWithArray:fragmentCollection.allKeys]);
    }
}

- (void)testNULLsWithGetter
{
    XCTAssertNoThrow([self runCategoryTest:nil expectParamCount:0 expectQueryCount:0 expectFragmentCount:0]);
    XCTAssertNoThrow(self.allPartsURL.tnl_parameterStringCollection);
    XCTAssertNoThrow(self.allPartsURL.tnl_queryCollection);
    XCTAssertNoThrow(self.allPartsURL.tnl_fragmentCollection);
}

- (void)testNilNSURLCategory
{
    [self runCategoryTest:self.pathURL expectParamCount:0 expectQueryCount:0 expectFragmentCount:0];
}

- (void)testPathNSURLCategory
{
    [self runCategoryTest:self.pathURL expectParamCount:0 expectQueryCount:0 expectFragmentCount:0];
}

- (void)testParameterStringNSURLCategory
{
    [self runCategoryTest:self.paramURL expectParamCount:ARG_COUNT expectQueryCount:0 expectFragmentCount:0];
}

- (void)testQueryNSURLCategory
{
    [self runCategoryTest:self.queryURL expectParamCount:0 expectQueryCount:ARG_COUNT expectFragmentCount:0];
}

- (void)testFragmentNSURLCategory
{
    [self runCategoryTest:self.fragmentURL expectParamCount:0 expectQueryCount:0 expectFragmentCount:ARG_COUNT];
}

- (void)testAllNSURLCategory
{
    [self runCategoryTest:self.allPartsURL expectParamCount:ARG_COUNT expectQueryCount:ARG_COUNT expectFragmentCount:ARG_COUNT];
}

- (void)testMutation
{
    TNLMutableParameterCollection *params;
    NSString *paramStringOld;
    NSString *paramStringCurrent;

    params = [[self.allPartsURL tnl_parameterStringCollection] mutableCopy];
    paramStringCurrent = params.stableURLEncodedStringValue;
    paramStringOld = paramStringCurrent;
    XCTAssertEqual(params.count, ARG_COUNT);
    XCTAssertEqualObjects(paramStringOld, paramStringCurrent);
    paramStringOld = paramStringCurrent;

    [params addParametersFromURL:self.pathURL parsingParameterTypes:TNLParameterTypeURLFragment | TNLParameterTypeURLParameterString | TNLParameterTypeURLQuery options:0];
    paramStringCurrent = params.stableURLEncodedStringValue;
    XCTAssertEqual(params.count, ARG_COUNT);
    XCTAssertEqualObjects(paramStringOld, paramStringCurrent);
    paramStringOld = paramStringCurrent;

    [params addParametersFromURL:self.allPartsURL parsingParameterTypes:TNLParameterTypeNone options:0];
    paramStringCurrent = params.stableURLEncodedStringValue;
    XCTAssertEqual(params.count, ARG_COUNT);
    XCTAssertEqualObjects(paramStringOld, paramStringCurrent);
    paramStringOld = paramStringCurrent;

    [params addParametersFromParameterCollection:params combineRepeatingKeys:NO];
    paramStringCurrent = params.stableURLEncodedStringValue;
    XCTAssertEqual(params.count, ARG_COUNT);
    XCTAssertEqualObjects(paramStringOld, paramStringCurrent);
    paramStringOld = paramStringCurrent;

    [params addParametersFromURL:self.allPartsURL parsingParameterTypes:TNLParameterTypeURLQuery options:0];
    paramStringCurrent = params.stableURLEncodedStringValue;
    XCTAssertEqual(params.count, ARG_COUNT * 2);
    XCTAssertNotEqualObjects(paramStringOld, paramStringCurrent);
    paramStringOld = paramStringCurrent;

    [params addParametersFromParameterCollection:self.allPartsURL.tnl_fragmentCollection combineRepeatingKeys:NO];
    paramStringCurrent = params.stableURLEncodedStringValue;
    XCTAssertEqual(params.count, ARG_COUNT * 3);
    XCTAssertNotEqualObjects(paramStringOld, paramStringCurrent);
    paramStringOld = paramStringCurrent;

    params[@"ten"] = @"10";
    params[@"nine"] = @"9";
    params[@"eight"] = @"8";
    XCTAssertTrue([@"8" isEqualToString:params[@"eight"]]);
    XCTAssertNoThrow((params[@"eight"] = nil)); // don't throw on nil entry, just remove
    XCTAssertTrue(nil == params[@"eight"]);
    params[@"eight"] = @"8";
    XCTAssertTrue([@"8" isEqualToString:params[@"eight"]]);
    params[@"seven"] = @"7";
    params[@"six"] = @"6";

    paramStringCurrent = params.stableURLEncodedStringValue;
    XCTAssertEqual(params.count, ARG_COUNT * 4);
    XCTAssertNotEqualObjects(paramStringOld, paramStringCurrent);
    paramStringOld = paramStringCurrent;
}

- (void)testOptions
{
    NSString *encodedString;
    TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] init];

    params[@"zero"] = @"zero";
    params[@"one"] = @"1";
    params[@"two"] = @2;
    params[@"three"] = @3.14;
    params[@"four"] = @YES;
    params[@"five"] = self;
    params[@"six"] = [[NSScanner alloc] init];
    params[@"seven"] = @"";
    params[@"eight"] = [@300 tnl_booleanObject];
    params[@"nine"] = [NSURL URLWithString:@"http://www.twitter.com/jack"];
    params[@"ten"] = params.underlyingDictionaryValue.allValues;

    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=1&one=1&seven=&three=3.14&two=2&zero=zero");
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionTrimEmptyValueDelimiter];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=1&one=1&seven&three=3.14&two=2&zero=zero");
    XCTAssertThrows([params URLEncodedStringValueWithOptions:TNLURLEncodingOptionStableOrder]);
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty];
    XCTAssertEqualObjects(encodedString, @"eight=true&five=&four=1&nine=&one=1&seven=&six=&ten=&three=3.14&two=2&zero=zero");
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty];
    XCTAssertEqualObjects(encodedString, @"eight=true&five=&four=1&nine=&one=1&seven=&six=&ten=&three=3.14&two=2&zero=zero");
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty | TNLURLEncodingOptionTrimEmptyValueDelimiter];
    XCTAssertEqualObjects(encodedString, @"eight=true&five&four=1&nine&one=1&seven&six&ten&three=3.14&two=2&zero=zero");
    sSupportCustomEncoding = YES;
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder];
    XCTAssertEqualObjects(encodedString, @"eight=true&five=TNLParameterCollectionTests&four=1&nine=http%3A%2F%2Fwww.twitter.com%2Fjack&one=1&seven=&ten=1%2C1%2C2%2C3.14%2CTNLParameterCollectionTests%2Chttp%3A%2F%2Fwww.twitter.com%2Fjack%2Ctrue%2Czero&three=3.14&two=2&zero=zero");
    sSupportCustomEncoding = NO;

    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=1&one=1&seven=&ten=&ten=1&ten=1&ten=2&ten=3.14&ten=true&ten=zero&three=3.14&two=2&zero=zero");
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionTrimEmptyValueDelimiter | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=1&one=1&seven&ten&ten=1&ten=1&ten=2&ten=3.14&ten=true&ten=zero&three=3.14&two=2&zero=zero");
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&five=&four=1&nine=&one=1&seven=&six=&ten=&ten=&ten=&ten=&ten=1&ten=1&ten=2&ten=3.14&ten=true&ten=zero&three=3.14&two=2&zero=zero");
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty | TNLURLEncodingOptionTrimEmptyValueDelimiter | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&five&four=1&nine&one=1&seven&six&ten&ten&ten&ten&ten=1&ten=1&ten=2&ten=3.14&ten=true&ten=zero&three=3.14&two=2&zero=zero");
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionDiscardEmptyValues | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=1&one=1&ten=1&ten=1&ten=2&ten=3.14&ten=true&ten=zero&three=3.14&two=2&zero=zero");
    sSupportCustomEncoding = YES;
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&five=TNLParameterCollectionTests&four=1&nine=http%3A%2F%2Fwww.twitter.com%2Fjack&one=1&seven=&ten=&ten=1&ten=1&ten=2&ten=3.14&ten=TNLParameterCollectionTests&ten=http%3A%2F%2Fwww.twitter.com%2Fjack&ten=true&ten=zero&three=3.14&two=2&zero=zero");
    sSupportCustomEncoding = NO;
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionDiscardEmptyValues | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty | TNLURLEncodingOptionDuplicateEntriesForArrayValues | TNLURLEncodingOptionEncodeBooleanNumbersAsTrueOrFalse];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=true&one=1&ten=1&ten=2&ten=3.14&ten=true&ten=true&ten=zero&three=3.14&two=2&zero=zero");

    // URL Encoding of value yields NULL instead of valid NSString...rare case that is being triggered for some users.

    sSupportCustomEncoding = NO;
#if DEBUG
    TNLSetDebugSTOPOnAssertEnabled(NO);
#endif
    TestBenignAssertionHandler *newHandler = [[TestBenignAssertionHandler alloc] init];
    NSAssertionHandler *oldHandler = [[NSThread currentThread] threadDictionary][NSAssertionHandlerKey];
    [[NSThread currentThread] threadDictionary][NSAssertionHandlerKey] = newHandler;
    NSString *str = [(id)[InvalidString alloc] init];
    params[@"another"] = str;
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=1&one=1&seven=&ten=&ten=1&ten=1&ten=2&ten=3.14&ten=true&ten=zero&three=3.14&two=2&zero=zero");

    XCTAssertGreaterThan(newHandler.assertCount, (NSUInteger)0);
    if (oldHandler) {
        [[NSThread currentThread] threadDictionary][NSAssertionHandlerKey] = oldHandler;
    } else {
        [[[NSThread currentThread] threadDictionary] removeObjectForKey:NSAssertionHandlerKey];
    }
#if DEBUG
    TNLSetDebugSTOPOnAssertEnabled(YES);
#endif

    sSupportCustomEncoding = NO;
#if DEBUG
    TNLSetDebugSTOPOnAssertEnabled(NO);
#endif
    str = @"abc🐱abc";
    str = [str substringWithRange:NSMakeRange(4,2)];
    newHandler = [[TestBenignAssertionHandler alloc] init];
    oldHandler = [[NSThread currentThread] threadDictionary][NSAssertionHandlerKey];
    [[NSThread currentThread] threadDictionary][NSAssertionHandlerKey] = newHandler;
    params[@"another"] = str;
    encodedString = [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionStableOrder | TNLURLEncodingOptionDuplicateEntriesForArrayValues];
    XCTAssertEqualObjects(encodedString, @"eight=true&four=1&one=1&seven=&ten=&ten=1&ten=1&ten=2&ten=3.14&ten=true&ten=zero&three=3.14&two=2&zero=zero");
    XCTAssertGreaterThan(newHandler.assertCount, (NSUInteger)0);
    if (oldHandler) {
        [[NSThread currentThread] threadDictionary][NSAssertionHandlerKey] = oldHandler;
    } else {
        [[[NSThread currentThread] threadDictionary] removeObjectForKey:NSAssertionHandlerKey];
    }
#if DEBUG
    TNLSetDebugSTOPOnAssertEnabled(YES);
#endif
}

- (void)testURLEncodableDictionary
{
    TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] init];

    params[@"zero"] = @"zero";
    params[@"one"] = @"1";
    params[@"two"] = @2;
    params[@"three"] = @3.14;
    params[@"four"] = @YES;
    params[@"five"] = self;
    params[@"six"] = [[NSScanner alloc] init];
    params[@"seven"] = @"";
    params[@"eight"] = @[@"1", @2, @[ @"3", @4] ];
    params[@"nine"] = @{ @"5" : @6, @"7" : @{ @"8" : @9 } };
    params[@"ten"] = [NSURL URLWithString:@"http://www.twitter.com/jack"];

    NSDictionary *expected = nil;
    TNLURLEncodableDictionaryOptions options = TNLURLEncodableDictionaryOptionsNone;

    XCTAssertThrows([self executeTestWithParams:params options:options supportingCustom:NO expected:nil]);
    XCTAssertThrows([self executeTestWithParams:params options:options supportingCustom:YES expected:nil]);

    XCTAssertFalse([TNLURLEncodableDictionary(@{ @"1" : @"2" }, 0) respondsToSelector:@selector(setObject:forKey:)]);
    XCTAssertTrue([TNLURLEncodableDictionary(@{ @"1" : @"2" }, TNLURLEncodableDictionaryOptionOutputMutableDictionary) respondsToSelector:@selector(setObject:forKey:)]);
    //
    options = TNLURLEncodableDictionaryOptionIgnoreUnsupportedValues;

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  @"seven" : @"",
                  };
    [self executeTestWithParams:params options:options supportingCustom:NO expected:expected];

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  @"five" : @"TNLParameterCollectionTests",
                  @"seven" : @"",
                  @"eight" : @"1,2,3,4",
                  @"ten" : @"http://www.twitter.com/jack",
                  };
    [self executeTestWithParams:params options:options supportingCustom:YES expected:expected];

    //
    options = TNLURLEncodableDictionaryOptionTreatUnsupportedValuesAsEmpty | TNLURLEncodableDictionaryOptionDiscardEmptyValues;

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  };
    [self executeTestWithParams:params options:options supportingCustom:NO expected:expected];

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  @"five" : @"TNLParameterCollectionTests",
                  @"eight" : @"1,2,3,4",
                  @"ten" : @"http://www.twitter.com/jack",
                  };
    [self executeTestWithParams:params options:options supportingCustom:YES expected:expected];

    //
    options = TNLURLEncodableDictionaryOptionTreatUnsupportedValuesAsEmpty;

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  @"five" : @"",
                  @"six" : @"",
                  @"seven" : @"",
                  @"eight" : @"",
                  @"nine" : @"",
                  @"ten" : @"",
                  };
    [self executeTestWithParams:params options:options supportingCustom:NO expected:expected];

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  @"five" : @"TNLParameterCollectionTests",
                  @"six" : @"",
                  @"seven" : @"",
                  @"eight" : @"1,2,3,4",
                  @"nine" : @"",
                  @"ten" : @"http://www.twitter.com/jack",
                  };
    [self executeTestWithParams:params options:options supportingCustom:YES expected:expected];

    //
    options = TNLURLEncodableDictionaryOptionIgnoreUnsupportedValues | TNLURLEncodableDictionaryOptionReplaceArraysWithArraysOfEncodableStrings | TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings;

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  @"seven" : @"",
                  @"eight" : @[ @"1", @2, @[ @"3", @4 ]],
                  @"nine" : @{ @"5" : @6, @"7" : @{ @"8" : @9 } }
                  };
    [self executeTestWithParams:params options:options supportingCustom:NO expected:expected];

    expected = @{ @"zero" : @"zero",
                  @"one" : @"1",
                  @"two" : @2,
                  @"three" : @3.14,
                  @"four" : @YES,
                  @"five" : @"TNLParameterCollectionTests",
                  @"seven" : @"",
                  @"eight" : @[ @"1", @2, @[ @"3", @4 ]],
                  @"nine" : @{ @"5" : @6, @"7" : @{ @"8" : @9 } },
                  @"ten" : @"http://www.twitter.com/jack",
                  };
    [self executeTestWithParams:params options:options supportingCustom:YES expected:expected];
}

- (void)executeTestWithParams:(TNLParameterCollection *)params options:(TNLURLEncodableDictionaryOptions)options supportingCustom:(BOOL)supportingCustom expected:(NSDictionary *)expected
{
    sSupportCustomEncoding = supportingCustom;
    NSException *exception = nil;
    @try {
        NSDictionary *dict = [params encodableDictionaryValueWithOptions:options];
        XCTAssertEqualObjects(expected, dict, @"options = 0x%zx", (long)options);
    }
    @catch (NSException *e) {
        exception = e;
    }
    sSupportCustomEncoding = NO;
    if (exception) {
        @throw exception; // rethrow
    }
}

- (void)testEmptyKey
{
    TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] init];
    XCTAssertNoThrow([params setParameterValue:@0 forKey:@"0"]);
    XCTAssertThrows([params setParameterValue:@0 forKey:(NSString * __nonnull)nil]);
    XCTAssertThrows([params setParameterValue:@0 forKey:@""]);
    XCTAssertThrows([params setParameterValue:@0 forKey:(NSString *)@0]);
    XCTAssertEqual((NSUInteger)1, (NSUInteger)params.count);
}

- (void)testAddingDictionaries
{
    TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] init];
    NSDictionary *dict = @{
                           @"key1" : @"value1",
                           @"key3" : @"value3",
                           @"key2" : @"value2",
                           };
    NSString *encodedString;

    // 1) Use Keys Directly

    [params removeAllParameters];
    [params addParametersFromDictionary:dict withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeUseKeysDirectly combineRepeatingKeys:NO forKey:@"dict"];
    encodedString = [params stableURLEncodedStringValue];
    XCTAssertEqualObjects(encodedString, @"key1=value1&key2=value2&key3=value3");

    // 2) URL Encoded

    [params removeAllParameters];
    [params addParametersFromDictionary:dict withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeURLEncoded combineRepeatingKeys:NO forKey:@"dict"];
    encodedString = [params stableURLEncodedStringValue];
    XCTAssertEqualObjects(encodedString, @"dict=key1%3Dvalue1%26key2%3Dvalue2%26key3%3Dvalue3");

    // 3) JSON Encoded

    [params removeAllParameters];
    [params addParametersFromDictionary:dict withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeJSONEncoded combineRepeatingKeys:NO forKey:@"dict"];
    encodedString = [params stableURLEncodedStringValue];

    if (@available(iOS 11.0, macos 10.13, watchos 4.0, tvos 11.0, *)) {
        // will be sorted
        XCTAssertEqualObjects(encodedString, @"dict=%7B%22key1%22%3A%22value1%22%2C%22key2%22%3A%22value2%22%2C%22key3%22%3A%22value3%22%7D");
    } else {
        // unsorted, need to check all variations :(

#define CHECK_STRING(first, second, third) @"dict=%7B%22key" #first "%22%3A%22value" #first "%22%2C%22key" #second "%22%3A%22value" #second "%22%2C%22key" #third "%22%3A%22value" #third "%22%7D"

        if (!encodedString) {
            XCTAssertNotNil(encodedString);
        } else if ([encodedString isEqualToString:CHECK_STRING(1, 2, 3)]) {
            XCTAssertTrue(YES);
        } else if ([encodedString isEqualToString:CHECK_STRING(1, 3, 2)]) {
            XCTAssertTrue(YES);
        } else if ([encodedString isEqualToString:CHECK_STRING(2, 1, 3)]) {
            XCTAssertTrue(YES);
        } else if ([encodedString isEqualToString:CHECK_STRING(2, 3, 1)]) {
            XCTAssertTrue(YES);
        } else if ([encodedString isEqualToString:CHECK_STRING(3, 1, 2)]) {
            XCTAssertTrue(YES);
        } else if ([encodedString isEqualToString:CHECK_STRING(3, 2, 1)]) {
            XCTAssertTrue(YES);
        } else {
            XCTAssertTrue(NO, @"%@ is the wrong encodedString!", encodedString);
        }
    }

#undef CHECK_STRING

    // 4) Dot-syntax

    [params removeAllParameters];
    [params addParametersFromDictionary:dict withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeDotSyntaxOnProvidedKey combineRepeatingKeys:NO forKey:@"dict"];
    encodedString = [params stableURLEncodedStringValue];
    XCTAssertEqualObjects(encodedString, @"dict.key1=value1&dict.key2=value2&dict.key3=value3");
}

- (void)testUnderlyingVersusEncodableDictionaries
{
    sSupportCustomEncoding = YES;
    tnl_defer(^{
        sSupportCustomEncoding = NO;
    });

    NSDictionary *rawD = @{
                           @"one" : @1,
                           @"two" : @"2",
                           @"three" : [@YES tnl_booleanObject],
                           @"four" : [@NO tnl_booleanObject],
                           @"five" : [@5 tnl_booleanObject],
                           @"six" : @{
                                        @"six.one" : @1,
                                        @"six.two" : @"2",
                                        @"six.three" : @YES,
                                        @"six.four" : @NO,
                                        @"six.five" : [@5 tnl_booleanObject],
                                    },
                           @"seven" : @[ @1, @"2", @YES, [@NO tnl_booleanObject], [@5 tnl_booleanObject] ],
                           };
    NSDictionary *expectedEncodedD = @{
                           @"one" : @1,
                           @"two" : @"2",
                           @"three" : @"true",
                           @"four" : @"false",
                           @"five" : @"true",
                           @"six" : @{
                                   @"six.one" : @1,
                                   @"six.two" : @"2",
                                   @"six.three" : @YES,
                                   @"six.four" : @NO,
                                   @"six.five" : @"true",
                                   },
                           @"seven" : @[ @1, @"2", @YES, @"false", @"true" ],
                           };

    TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] initWithDictionary:rawD];

    NSDictionary *underlyingD;
    NSDictionary *encodedD;

    underlyingD = params.underlyingDictionaryValue;
    encodedD = params.encodableDictionaryValue;

    XCTAssertNotEqualObjects(underlyingD, encodedD);
    XCTAssertEqualObjects(underlyingD, rawD);
    XCTAssertEqualObjects(encodedD, expectedEncodedD);

    NSDate *date = [NSDate date];
    params[@"eight"] = date;
    underlyingD = params.underlyingDictionaryValue;
    XCTAssertEqualObjects(underlyingD[@"eight"], date);
    XCTAssertThrows((void)params.encodableDictionaryValue); // cannot encode NSDate without TNLURLEncodableObject conformance
}

#pragma mark TNLURLEncodableObject

- (NSString *)tnl_URLEncodableStringValue
{
    return (sSupportCustomEncoding) ? NSStringFromClass([self class]) : nil;
}

@end

@implementation TestBenignAssertionHandler

- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(NSInteger)line description:(NSString *)format,...
{
    _assertCount++;
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(NSInteger)line description:(NSString *)format,...
{
    _assertCount++;
}

@end

@implementation InvalidString
{
    NSString *_proxyString;
}

- (id)init
{
    _proxyString = @"fake string";
    return self;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    if (@selector(UTF8String) == invocation.selector || @selector(copyWithZone:) == invocation.selector || @selector(copy) == invocation.selector) {
        invocation.target = self;
    } else {
        invocation.target = _proxyString;
    }
    [invocation invoke];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    if (sel == @selector(UTF8String) || sel == @selector(copyWithZone:) || sel == @selector(copy)) {
        return [super methodSignatureForSelector:sel];
    }

    return [_proxyString methodSignatureForSelector:sel];
}

- (const char *)UTF8String
{
    return NULL;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)copy
{
    return [self copyWithZone:nil];
}

@end

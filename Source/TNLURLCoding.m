//
//  TNLURLCoding.m
//  TwitterNetworkLayer
//
//  Created on 7/28/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSNumber+TNLURLCoding.h"
#import "TNL_Project.h"
#import "TNLURLCoding.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * __nullable TNLStringValue(id object,
                                            TNLURLEncodingOptions options,
                                            NSString * __nullable contextKey);
static NSString *TNLNumberStringValue(NSNumber *number);
static id __nullable TNLURLEncodableValue(id value,
                                          TNLURLEncodableDictionaryOptions options,
                                          NSString * __nullable contextKey);

static void TNLAppendKeyValuePairToMutableString(NSMutableString *string,
                                                 NSString *key,
                                                 NSString *value,
                                                 TNLURLEncodingOptions options);
static void TNLAppendParameterDelimeterIfNecessary(NSMutableString *parameterString,
                                                   BOOL *inoutIsFirstEntry);
static void TNLAppendEncodedKeyValuePair(NSMutableString *parameterString,
                                         NSString *encodedKey,
                                         NSString *encodedValue,
                                         TNLURLEncodingOptions options,
                                         BOOL *inoutIsFirstEntry);
static void TNLAppendArrayOfParameterValues(NSMutableString *parameterString,
                                            NSString *encodedKey,
                                            NSArray *values,
                                            TNLURLEncodingOptions options,
                                            BOOL *inoutIsFirstEntry);
static void TNLAppendParameterValue(NSMutableString *parameterString,
                                    NSString *encodedKey,
                                    id value,
                                    TNLURLEncodingOptions options,
                                    BOOL *inoutIsFirstEntry);

static NSArray *TNLURLConvertArrayToArrayOfEncodableStrings(NSArray * __nullable sourceArray,
                                                            TNLURLEncodableDictionaryOptions options,
                                                            NSString * __nullable contextKey);
static NSDictionary *TNLURLConvertDictionaryToDictionaryOfEncodableStrings(NSDictionary * __nullable sourceDict,
                                                                           TNLURLEncodableDictionaryOptions options);

// See TNLURLStringCoding.m
// NSString *TNLURLEncodeString(NSString *string)

// See TNLURLStringCoding.m
// NSString *TNLURLDecodeString(NSString *string, BOOL replacePlussesWithSpaces)

static void TNLAppendKeyValuePairToMutableString(NSMutableString *string,
                                                 NSString *key,
                                                 NSString *value,
                                                 TNLURLEncodingOptions options)
{
    TNLAssert(string != nil);
    TNLAssert(key != nil);
    TNLAssert(value != nil);
    if (key && string) {
        [string appendString:key];
        if ((value.length > 0) || TNL_BITMASK_EXCLUDES_FLAGS(options, TNLURLEncodingOptionTrimEmptyValueDelimiter)) {
            [string appendString:@"="];
            if (value) {
                [string appendString:value];
            }
        }
    }
}

static void TNLAppendParameterDelimeterIfNecessary(NSMutableString *parameterString,
                                                   BOOL *inoutIsFirstEntry)
{
    if (!(*inoutIsFirstEntry)) {
        [parameterString appendString:@"&"];
    } else {
        *inoutIsFirstEntry = NO;
    }
}

static void TNLAppendEncodedKeyValuePair(NSMutableString *parameterString,
                                         NSString *encodedKey,
                                         NSString *encodedValue,
                                         TNLURLEncodingOptions options,
                                         BOOL *inoutIsFirstEntry)
{
    if (TNL_BITMASK_EXCLUDES_FLAGS(options, TNLURLEncodingOptionDiscardEmptyValues) || (encodedValue.length > 0)) {
        TNLAppendParameterDelimeterIfNecessary(parameterString, inoutIsFirstEntry);
        TNLAppendKeyValuePairToMutableString(parameterString, encodedKey, encodedValue, options);
    }
}

static void TNLAppendArrayOfParameterValues(NSMutableString *parameterString,
                                            NSString *encodedKey,
                                            NSArray *values,
                                            TNLURLEncodingOptions options,
                                            BOOL *inoutIsFirstEntry)
{
    NSMutableArray *encodedValues = [NSMutableArray arrayWithCapacity:[values count]];
    for (id subvalue in values) {
        NSString *stringValue = TNLStringValue(subvalue, options, encodedKey);
        if (stringValue) {
            stringValue = TNLURLEncodeString(stringValue);
            if (stringValue) {
                [encodedValues addObject:stringValue];
            }
        }
    }

    if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodingOptionStableOrder)) {
        [encodedValues sortUsingSelector:@selector(compare:)];
    }

    for (NSString *encodedValue in encodedValues) {
        TNLAppendEncodedKeyValuePair(parameterString, encodedKey, encodedValue, options, inoutIsFirstEntry);
    }
}

static void TNLAppendParameterValue(NSMutableString *parameterString,
                                    NSString *encodedKey,
                                    id value,
                                    TNLURLEncodingOptions options,
                                    BOOL *inoutIsFirstEntry)
{
    TNLAssert(encodedKey != nil);
    NSString *stringValue = TNLStringValue(value, options, encodedKey);
    if (stringValue) {
        NSString *encodedValue = TNLURLEncodeString(stringValue);
        if (!encodedValue) {
            TNLLogError(@"Could not encode value for encoded key '%@': '%@'", encodedKey, stringValue);
            TNLAssertMessage(encodedValue != nil, @"Could not encode value for encoded key '%@': '%@'", encodedKey, stringValue);

            // Handle the unexpected encoding of the value as an unsupported value

            if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty)) {
                encodedValue = @"";
            } else if (TNL_BITMASK_EXCLUDES_FLAGS(options, TNLURLEncodingOptionIgnoreUnsupportedValues)) {
                NSString *reason = [NSString stringWithFormat:@"parameter object cannot be URL Encoded (options=%@, object=%@, stringValue=%@, key=%@)", @(options), value, stringValue, encodedKey];
                @throw [NSException exceptionWithName:NSInvalidArgumentException
                                               reason:reason
                                             userInfo:@{ @"object" : (value) ?: [NSNull null], @"encodingOptions" : @(options) }];
            }
        }

        if (encodedKey && encodedValue) {
            TNLAppendEncodedKeyValuePair(parameterString, encodedKey, encodedValue, options, inoutIsFirstEntry);
        }
    }
}

NSString *TNLURLEncodeDictionary(NSDictionary * __nullable params,
                                 TNLURLEncodingOptions options)
{
    NSMutableString *parameterString = [NSMutableString string];

    NSArray *allKeys = params.allKeys;

    if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodingOptionStableOrder)) {
        allKeys = [allKeys sortedArrayUsingSelector:@selector(compare:)];
    }

    const BOOL specialCaseArrays = TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodingOptionDuplicateEntriesForArrayValues);
    BOOL firstEntry = YES;
    for (NSString *key in allKeys) {
        NSString *encodedKey = TNLURLEncodeString(key);
        if (encodedKey.length > 0) {
            id value = params[key];
            if (specialCaseArrays && [value isKindOfClass:[NSArray class]] && [value count] > 0) {
                TNLAppendArrayOfParameterValues(parameterString, encodedKey, value, options, &firstEntry);
            } else {
                TNLAppendParameterValue(parameterString, encodedKey, value, options, &firstEntry);
            }
        }
    }

    return parameterString;
}

NSDictionary *TNLURLDecodeDictionary(NSString * __nullable encodedURLString,
                                     TNLURLDecodingOptions options)
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSArray *pairs = [encodedURLString componentsSeparatedByString:@"&"];
    const BOOL preserveEmptyValues = TNL_BITMASK_EXCLUDES_FLAGS(options, TNLURLDecodingOptionOmitEmptyValues);
    const BOOL replacePlusses = TNL_BITMASK_EXCLUDES_FLAGS(options, TNLURLDecodingOptionPreservePlusses);
    const BOOL combineRepeatingKeys = TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLDecodingOptionCombineRepeatingKeysIntoArray);
    for (NSString *pair in pairs) {
        if (pair.length) {
            const NSRange delimeterRange = [pair rangeOfString:@"="];
            NSString *key = nil;
            NSString *value = nil;
            if (delimeterRange.location != NSNotFound) {
                key = [pair substringToIndex:delimeterRange.location];
                value = [pair substringFromIndex:delimeterRange.location + delimeterRange.length];
                if (value.length == 0) {
                    value = preserveEmptyValues ? @"" : nil;
                }
            } else if (preserveEmptyValues) {
                key = pair;
                value = @"";
            }

            if (nil != value && nil != key) {
                value = TNLURLDecodeString(value, replacePlusses);
                key = TNLURLDecodeString(key, replacePlusses);

                if (nil != value && key.length > 0) {
                    if (combineRepeatingKeys) {
                        id oldValue = dict[key];
                        if ([oldValue isKindOfClass:[NSString class]]) {
                            dict[key] = [NSMutableArray arrayWithObjects:oldValue, value, nil];
                        } else if ([oldValue isKindOfClass:[NSArray class]]) {
                            [(NSMutableArray *)oldValue addObject:value];
                        } else {
                            dict[key] = value;
                        }
                    } else {
                        dict[key] = value;
                    }
                }
            }
        }
    }
    return TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLDecodingOptionOutputMutableDictionary) ? dict : [dict copy];
}

static NSArray *TNLURLConvertArrayToArrayOfEncodableStrings(NSArray * __nullable sourceArray,
                                                            TNLURLEncodableDictionaryOptions options,
                                                            NSString * __nullable contextKey)
{
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:sourceArray.count];

    for (__strong id value in sourceArray) {
        value = TNLURLEncodableValue(value, options, contextKey);
        if (value) {
            [array addObject:value];
        }
    }

    return [array copy];
}

static NSDictionary *TNLURLConvertDictionaryToDictionaryOfEncodableStrings(NSDictionary * __nullable sourceDict,
                                                                           TNLURLEncodableDictionaryOptions options)
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:sourceDict.count];

    for (NSString *key in sourceDict) {
        id value = sourceDict[key];
        value = TNLURLEncodableValue(value, options, key);
        if (value) {
            dict[key] = value;
        }
    }

    return [dict copy];
}

NSDictionary *TNLURLEncodableDictionary(NSDictionary * __nullable params,
                                        TNLURLEncodableDictionaryOptions options)
{
    TNLStaticAssert(TNLURLEncodableDictionaryOptionDiscardEmptyValues == TNLURLEncodingOptionDiscardEmptyValues, DiscardEmptyValuesOptionsAreNotEqual);
    TNLStaticAssert(TNLURLEncodableDictionaryOptionIgnoreUnsupportedValues == TNLURLEncodingOptionIgnoreUnsupportedValues, IgnoreUnsupportedValuesOptionsAreNotEqual);
    TNLStaticAssert(TNLURLEncodableDictionaryOptionTreatUnsupportedValuesAsEmpty == TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty, TreatUnsupportedValuesAsEmptyOptionsAreNotEqual);

    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:params.count];

    NSArray *allKeys = params.allKeys;

    for (NSString *key in allKeys) {
        id value = params[key];
        value = TNLURLEncodableValue(value, options, key);

        if (value) {
            dict[key] = value;
        }
    }

    return TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodableDictionaryOptionOutputMutableDictionary) ? dict : [dict copy];
}

// This function is ~15% more performant than `-[NSNumber stringValue]` -- which matters when encoding values as rapidly and often as TNL does
static NSString *TNLNumberStringValue(NSNumber *number)
{
    static NSString * __nonnull kSmallPositives[] = { @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9" };
    const char *objCType = [number objCType];
    if (objCType) {
        switch (*objCType) {
            case 'c':
            case 'i':
            case 's':
            case 'l':
            case 'q':
            {
                const long long value = [number longLongValue];
                if (value < 10 && value >= 0) {
                    return kSmallPositives[value];
                }
                return [[NSString alloc] initWithFormat:@"%lli", value];
            }
            case 'C':
            case 'I':
            case 'S':
            case 'L':
            case 'Q':
            {
                const unsigned long long value = [number unsignedLongLongValue];
                if (value < 10) {
                    return kSmallPositives[value];
                }
                return [[NSString alloc] initWithFormat:@"%llu", value];
            }
            case 'f':
                return [[NSString alloc] initWithFormat:@"%0.7g", [number floatValue]];
            case 'd':
                return [[NSString alloc] initWithFormat:@"%0.16g", [number doubleValue]];
            default:
                break;
        }
    }

    return [number descriptionWithLocale:nil];
}

static NSString *TNLStringValue(id object,
                                TNLURLEncodingOptions options,
                                NSString * __nullable contextKey)
{
    NSString *value = nil;
    if ([object isKindOfClass:[NSString class]]) {
        value = object;
    } else if ([object isKindOfClass:[NSNumber class]]) {
        if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodingOptionEncodeBooleanNumbersAsTrueOrFalse) && [object tnl_isBoolean]) {
            // use "true"/"false" instead of default "1"/"0"
            value = [object boolValue] ? @"true" : @"false";
        } else {
            value = TNLNumberStringValue(object);
        }
    } else if ([object respondsToSelector:@selector(tnl_URLEncodableStringValue)]) {
        value = [object tnl_URLEncodableStringValue];
    }

    if (!value && TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty)) {
        value = @"";
    }

    if (!value && TNL_BITMASK_EXCLUDES_FLAGS(options, TNLURLEncodingOptionIgnoreUnsupportedValues)) {
        NSString *reason = [NSString stringWithFormat:@"parameter object cannot be URL Encoded (options=%@, object=%@, key=%@)", @(options), value, contextKey];
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:@{ @"object" : (object) ?: [NSNull null], @"encodingOptions" : @(options) }];
    }

    return value;
}

static id TNLURLEncodableValue(id value,
                               TNLURLEncodableDictionaryOptions options,
                               NSString * __nullable contextKey)
{
    id returnValue;
    if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodableDictionaryOptionReplaceArraysWithArraysOfEncodableStrings) && [value isKindOfClass:[NSArray class]]) {
        returnValue = TNLURLConvertArrayToArrayOfEncodableStrings(value, options, contextKey);
    } else if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings) && [value isKindOfClass:[NSDictionary class]]) {
        returnValue = TNLURLConvertDictionaryToDictionaryOfEncodableStrings(value, options);
    } else if ([value isKindOfClass:[NSNumber class]]) {
        // NSNumbers are always OK
        returnValue = value;
    } else {
        const TNLURLEncodingOptions encodingOptions = (options & (TNLURLEncodingOptionDiscardEmptyValues |  TNLURLEncodingOptionIgnoreUnsupportedValues | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty));

        NSString *valueString = TNLStringValue(value, encodingOptions, contextKey);
        if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLEncodableDictionaryOptionDiscardEmptyValues) && (valueString.length == 0)) {
            valueString = nil;
        }
        returnValue = valueString;
    }
    return returnValue;
}

// Implemented in TNLURLCoding.m to utilize the static TNLNumberStringValue function
@implementation NSNumber (TNLStringCoding)

- (NSString *)tnl_quickStringValue
{
    return TNLNumberStringValue(self);
}

@end

NS_ASSUME_NONNULL_END

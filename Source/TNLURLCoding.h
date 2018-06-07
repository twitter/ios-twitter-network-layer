//
//  TNLURLCoding.h
//  TwitterNetworkLayer
//
//  Created on 7/28/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 TNLURLEncodingOptions

 Options for how to encode a `TNLParameterCollection` or `NSDictionary`
 */
typedef NS_OPTIONS(NSInteger, TNLURLEncodingOptions) {
    /**
     No options, behave with defaults
     */
    TNLURLEncodingOptionsNone = 0,
    /**
     URL Encode with the parameters being sorted by their keys
     */
    TNLURLEncodingOptionStableOrder = (1 << 0),
    /**
     URL Encode such that parameters with empty values will be discarded.
     Mutually exclusive with `TrimEmptyValueDelimiter` - if both are defined,
     `DiscardEmptyValueDelimiter` will take preference.
     */
    TNLURLEncodingOptionDiscardEmptyValues = (1 << 1),
    /**
     URL Encode such that the value delimiter, `'='`, is trimmed for empty parameter values.
     Example: `params[@"key"] = @""` -> `@"key"` instead of `@"key="`.
     Mutually exclusive with `DiscardEmptyValues` - if both are defined,
     `DiscardEmptyValues` will take preference.
     */
    TNLURLEncodingOptionTrimEmptyValueDelimiter = (1 << 2),
    /**
     By default, unsupported values will throw an exception.
     This option ignores unsupported values when they are encountered.
     `TreatUnsupportedValuesAsEmpty` takes precedence over `IgnoreUnsupportedValues`.
     */
    TNLURLEncodingOptionIgnoreUnsupportedValues = (1 << 3),
    /**
     By default, unsupported values will throw an exception.
     This option will treat unsupported values as empty values.
     `TreatUnsupportedValuesAsEmpty` takes precedence over `IgnoreUnsupportedValues`.
     */
    TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty = (1 << 4),
    /**
     If a value is an array, each entry will be encoded with the same key.
     Example: `params[@"key1"] = @[@"val1", @"val2"]` will be `@"key1=val1&key1=val2"`
     */
    TNLURLEncodingOptionDuplicateEntriesForArrayValues = (1 << 5),
    /**
     If a value is an NSNumber, discern Boolean values so they are encoded
     as `true` or `false` instead of `1` or `0`.
     Example: `params[@"key1"] = @YES` will be `@"key1=true` instead of `@"key1=1`
     @note the default of having `1` or `0` encoded was in order to bias towards the more compact
     representation.
     */
    TNLURLEncodingOptionEncodeBooleanNumbersAsTrueOrFalse = (1 << 6),
};

/**
 TNLURLDecodingOptions

 Options for how to decode an `NSString` representing a `TNLParameterCollection` or `NSDictionary`
 */
typedef NS_OPTIONS(NSInteger, TNLURLDecodingOptions) {
    /**
     No options
     */
    TNLURLDecodingOptionsNone = 0,
    /**
     When an key is encountered with no value, omit that parameter.
     Default will use an empty string as the parameter's value.
     */
    TNLURLDecodingOptionOmitEmptyValues = (1 << 0),
    /**
     When the same key is encountered more than once, turn the value for that parameter key into an
     array of values (preserving order).  Default, last value seen is used.
     */
    TNLURLDecodingOptionCombineRepeatingKeysIntoArray = (1 << 1),
    /**
     Output an `NSMutableDictionary` instead of an `NSDictionary`
     */
    TNLURLDecodingOptionOutputMutableDictionary = (1 << 2),
    /**
     Preserve (reserved) `'+'` character instead of replacing it with `' '` character when decoding
     */
    TNLURLDecodingOptionPreservePlusses = (1 << 3),
};

/**
 TNLURLEncodableDictionaryOptions

 Options for how to convert parameters into a dictionary of encodable strings.
 */
typedef NS_OPTIONS(NSInteger, TNLURLEncodableDictionaryOptions){
    /**
     No options
     */
    TNLURLEncodableDictionaryOptionsNone = 0,
    /**
     Currently reserved.  Do not use.
     */
    TNLURLEncodableDictionaryOptionReserved = (1 << 0),
    /**
     Any value that ends up being an empty string will be discarded
     */
    TNLURLEncodableDictionaryOptionDiscardEmptyValues = (1 << 1),
    /**
     Instead of returning an `NSDictionary`, return an `NSMutableDictionary`.
     */
    TNLURLEncodableDictionaryOptionOutputMutableDictionary = (1 << 2),
    /**
     By default, unsupported values will throw an exception.
     This option ignores unsupported values when they are encountered.
     `TreatUnsupportedValuesAsEmpty` takes precedence over `IgnoreUnsupportedValues`.
     */
    TNLURLEncodableDictionaryOptionIgnoreUnsupportedValues = (1 << 3),
    /**
     By default, unsupported values will throw an excpetion.
     This option will treat unsupported values as empty values.
     `TreatUnsupportedValuesAsEmpty` takes precedence over `IgnoreUnsupportedValues`.
     */
    TNLURLEncodableDictionaryOptionTreatUnsupportedValuesAsEmpty = (1 << 4),
    /**
     By default, arrays are treated like any other value and will only be supported if
     `tnl_URLEncodableStringValue` is implemented.
     This option will convert encountered arrays of values into arrays of encodable strings.
     This option applies recursively.
     */
    TNLURLEncodableDictionaryOptionReplaceArraysWithArraysOfEncodableStrings = (1 << 5),
    /**
     By default, dictionaries are treated like any other value and will only be supported if
     `tnl_URLEncodableStringValue` is implemented.
     This option will convert encountered dictionaries of values into dictionaries of encodable strings.
     This option applies recursively.
     */
    TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings = (1 << 6),
};

/**
 Implicit protocol that any object can implement to add support for being encoded by an
 `TNLParameterCollection` or `TNLURLEncodeDictionary`.

 By default, `NSNumber` has a category in __TNL__ to provide `TNLURLEncodableObject`.
 See `NSNumber(TNLURLCoding)`.
 */
@protocol TNLURLEncodableObject <NSObject>
/**
 Implementers return a string representation to be URL Encoded.
 Returning `nil` indicates the object does not support URL Encoding.
 @note __DO NOT__ URL encode the returned value since the URL encoding function will do that.
 */
- (nullable NSString *)tnl_URLEncodableStringValue;
@end

FOUNDATION_EXTERN NSString * __nullable TNLURLEncodeString(NSString * __nullable string);
FOUNDATION_EXTERN NSString * __nullable TNLURLDecodeString(NSString * __nullable string,
                                                           BOOL replacePlussesWithSpaces);

FOUNDATION_EXTERN NSString * __nullable TNLURLEncodeDictionary(NSDictionary<NSString *, id> * __nullable params,
                                                               TNLURLEncodingOptions options);
FOUNDATION_EXTERN NSDictionary<NSString *, id> * __nullable TNLURLDecodeDictionary(NSString * __nullable encodedURLString,
                                                                                   TNLURLDecodingOptions options);

FOUNDATION_EXTERN NSDictionary<NSString *, id> * __nullable TNLURLEncodableDictionary(NSDictionary<NSString *, id> * __nullable params,
                                                                                      TNLURLEncodableDictionaryOptions options);

#if APPLEDOC
/**
 TNLURL APIs

 # URL Encoding/Decoding

 ### TNLURLEncodeString

 URL Encode String - per http://tools.ietf.org/html/rfc5849 3.6. Percent Encoding

 - Characters in the unreserved character set as defined by [RFC3986], Section 2.3 (ALPHA, DIGIT, "-", ".", "_", "~") MUST NOT be encoded.
 - All other characters MUST be encoded.
 - The two hexadecimal characters used to represent encoded characters MUST be uppercase.

 __Parameters:__

 _string_ the string to encode

 __Returns:__ A URL Encoded string

    FOUNDATION_EXTERN NSString *TNLURLEncodeString(NSString *string);

 ### TNLURLDecodeString

 Decode a URL Encoded String

 __Parameters:__

 _string_                   the URL Encoded string to decode
 _replacePlussesWithSpaces_ YES to replace `'+'` characters with spaces

 __Returns:__ the decoded string

    FOUNDATION_EXTERN NSString *TNLURLDecodeString(NSString *string,
                                                   BOOL replacePlussesWithSpaces);

 ### TNLURLEncodeDictionary

 Convert a dictionary of key value pairs into a URL Encoded String.

 __Format:__ `@"key1=value1&key2=value2&..."` where keys and values are URL Encoded

 __Parameters__:

 _params_   the dictionary of key/value pairs
 _options_  the options to encode with.  See `TNLURLEncodingOptions`.

 __Returns:__ A URL Encoded string

    FOUNDATION_EXTERN NSString *TNLURLEncodeDictionary(NSDictionary *params,
                                                       TNLURLEncodingOptions options);

 ### TNLURLDecodeDictionary

 Convert a URL Encoded String into a dctionary of keys and values.

 __Parameters:__

 _encodedURLString_     the URL Encoded string to decode
 _options_              the options to decode with.  See `TNLURLDecodingOptions`.
 __NOTE:__ if a key or it's value cannot be transformed into a normal string with `TNLURLDecodeString`, the parameter will be omitted.

    FOUNDATION_EXTERN NSDictionary *TNLURLDecodeDictionary(NSString *encodedURLString,
                                                           TNLURLDecodingOptions options);

 ### TNLURLEncodableDictionary

 Convert a dictionary of key value pairs into a dictionary that only contains `NSString` values making the dictionary easily encodable as a URL Encoded String.

 __Parameters__:

 _params_   the dictionary of key/value pairs
 _options_  the options to convert the values with.  See `TNLURLEncodableDictionaryOptions`.

 __Returns:__ An `NSDictionary` that only contains `NSString` values.  Can contain `NSArray` values or `NSDictionary` values too based on the _options_ used.

    FOUNDATION_EXTERN NSDictionary *TNLURLEncodableDictionary(NSDictionary *params,
                                                              TNLURLEncodableDictionaryOptions options);

 */
@interface TNLURL_APIs
@end
#endif

NS_ASSUME_NONNULL_END

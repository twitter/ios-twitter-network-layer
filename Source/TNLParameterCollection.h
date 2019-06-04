//
//  TNLParameterCollection.h
//  TwitterNetworkLayer
//
//  Created on 10/24/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TwitterNetworkLayer/TNLURLCoding.h>

NS_ASSUME_NONNULL_BEGIN

/**
 TNLParameterTypes

 Options to specify a set of parameter types that can be ORed together
 */
typedef NS_OPTIONS(NSInteger, TNLParameterTypes) {
    /** No type */
    TNLParameterTypeNone = 0,
    /**
     The URL Parameter String.  Delimited with a ';'.
     @warning parameter string pattern in a URL is now considered deprecated behavior and `NSURL` will treat ';' delimited parameter string as part of the URL's path.  __TNL__ will continue to parse `TNLParameterTypesURLParameterString` for compatibility, but it is recommend that passing arguments via URL be done using query or fragment delimiters.
     */
    TNLParameterTypeURLParameterString = (1 << 0),
    /** The URL Query.  Delimited with a '?'. */
    TNLParameterTypeURLQuery = (1 << 1),
    /** The URL Fragment.  Delimited with a '#'. */
    TNLParameterTypeURLFragment = (1 << 2),
};

/**
 TNLParameterCollectionAddParametersFromDictionaryMode

 Adding dictionaries to a `TNLParameterCollection` can be done in many ways and thus is ambiguous without providing the mode to add the dictionary keys and values.

 *Examples for each mode:*

 ### TNLParameterCollectionAddParametersFromDictionaryModeUseKeysDirectly

 Use the keys from the dictionary directly in the parameter collection, thus ignoring the provided _key_.

    [params addParametersFromDictionary:@{ @"key1" : @"value1", @"key2" : @"value2" }
                     withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeUseKeysDirectly
                   combineRepeatingKeys:NO
                                 forKey:@"dict"];
    // ... equivalent to ...
    params[@"key1"] = @"value1";
    params[@"key2"] = @"value2";
    // ... when params is URL encoded ...
    key1=value1&key2=value2

 ### TNLParameterCollectionAddParametersFromDictionaryModeURLEncoded

 URL Encode the dictionary and set it to the provided _key_ on the parameter collection.

    [params addParametersFromDictionary:@{ @"key1" : @"value1", @"key2" : @"value2" }
                     withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeURLEncoded
                   combineRepeatingKeys:NO
                                 forKey:@"dict"];
    // ... equivalent to ...
    params[@"dict"] = @"key1=value1&key2=value2";
    // ... when params is URL encoded ...
    dict=key1%3Dvalue1%26key2%3Dvalue2

 ### TNLParameterCollectionAddParametersFromDictionaryModeJSONEncoded

 JSON Encode the dictionary and set it to the provided _key_ on the parameter collection.

    [params addParametersFromDictionary:@{ @"key1" : @"value1", @"key2" : @"value2" }
                     withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeJSONEncoded
                   combineRepeatingKeys:NO
                                forKey:@"dict"];
    // ... equivalent to ...
    params[@"dict"] = @"{\"key1\"=\"value1\",\"key2\"=\"value2\"}";
    // ... when params is URL encoded ...
    dict=%7B%22key1%22%3A%22value1%22%2C%22key2%22%3A%22value2%22%7D

 ### TNLParameterCollectionAddParametersFromDictionaryModeDotSyntaxOnProvidedKey

 Dot-syntax on the provided _key_ with the dictionary's keys to set the values on the parameter collection.

    [params addParametersFromDictionary:@{ @"key1" : @"value1", @"key2" : @"value2" }
                     withFormattingMode:TNLParameterCollectionAddParametersFromDictionaryModeDotSyntaxOnProvidedKey
                   combineRepeatingKeys:NO
                                 forKey:@"dict"];
    // ... equivalent to ...
    params[@"dict.key1"] = @"value1";
    params[@"dict.key2"] = @"value2";
    // ... when params is URL encoded ...
    dict.key1=value1&dict.key2=value2

 */
typedef NS_ENUM(NSInteger, TNLParameterCollectionAddParametersFromDictionaryMode) {
    /**
     Use the keys from the dictionary directly in the parameter collection, thus ignoring the provided _key_.
     */
    TNLParameterCollectionAddParametersFromDictionaryModeUseKeysDirectly = 0,
    /**
     URL Encode the dictionary and set it to the provided _key_ on the parameter collection.
     */
    TNLParameterCollectionAddParametersFromDictionaryModeURLEncoded,
    /**
     JSON Encode the dictionary and set it to the provided _key_ on the parameter collection.
     */
    TNLParameterCollectionAddParametersFromDictionaryModeJSONEncoded,
    /**
     Dot-syntax on the provided _key_ with the dictionary's keys to set the values on the parameter collection.
     */
    TNLParameterCollectionAddParametersFromDictionaryModeDotSyntaxOnProvidedKey,
};

/**
 TNLParameterCollection

 An object for representing parameters that are URL Encoded as a string.

 Collections of parameters (in Key-Value-Pairs) are often used in URLs for their parameter string,
 query and fragment portions but can also be regularly used as the body of an HTTP Request or other
 key-value-pair use cases.

 This class turns these collections of key-value-pairs into a simple to use object that is very
 similar to a mutable dictionary and makes it easy to go to and from different representations of
 URL parameters.

 Since this class deals with encoding and decoding parameters to and from URL encoded strings, and
 that leaves room for variation, it is important to be familiar with `TNLURLEncodingOptions` and
 `TNLURLDecodingOptions` and how they affect encoding and decoding.

 This object has a mutable subclass: `TNLMutableParameterCollection`
 */
@interface TNLParameterCollection : NSObject <NSMutableCopying, NSSecureCoding, NSFastEnumeration>

#pragma mark Initializers

/** Designated initializer.  Collection with no parameters set. */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/** init with parameters parsed from the provided _params_ using the given _options_. */
- (instancetype)initWithURLEncodedString:(nullable NSString *)params
                                 options:(TNLURLDecodingOptions)options;

/** See `initWithURLEncodedString:options:` */
- (instancetype)initWithURLEncodedString:(nullable NSString *)params;

/** init with parameters from the provided _dictionary_.  Keys must all be `NSString` objects */
- (instancetype)initWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

/**
 init with parameters parsed from the provided _URL_ given the provided _options_.
 Filter what parameter type(s) to parse with the provided _types_.
 */
- (instancetype)initWithURL:(nullable NSURL *)URL
      parsingParameterTypes:(TNLParameterTypes)types
                    options:(TNLURLDecodingOptions)options;

/** See `initWithURL:parsingParameterTypes:options:` */
- (instancetype)initWithURL:(nullable NSURL *)URL
      parsingParameterTypes:(TNLParameterTypes)types;

/** init with another `TNLParameterCollection` */
- (instancetype)initWithParameterCollection:(nullable TNLParameterCollection *)otherCollection NS_DESIGNATED_INITIALIZER;

#pragma mark Base Methods

/**
 Get the parameter value for a given key.
 @param key The key to use.
 @return The value matching the _key_ or `nil` if not found
 */
- (nullable id)parameterValueForKey:(NSString *)key;

#pragma Inspection Methods

/** The number of parameters in the collection */
- (NSUInteger)count;
/** All the parameter keys */
- (NSArray<NSString *> *)allKeys;
/** Enumerate the parameter keys and values */
- (void)enumerateParameterKeysAndValuesUsingBlock:(void (^)(NSString *key, id paramValue, BOOL *stop))block;
/** Enumerate the parameter keys and values with options */
- (void)enumerateParameterKeysAndValuesWithOptions:(NSEnumerationOptions)opts
                                        usingBlock:(void (^)(NSString *key, id paramValue, BOOL *stop))block;

#pragma mark Conversion Methods

/** Convert the collection into a URL encoded string */
- (NSString *)URLEncodedStringValue;
/** Convert the collection into a URL encoded string, but maintaining stability by ordering the keys alphabetically */
- (NSString *)stableURLEncodedStringValue;
/** Convert the collection into a URL encoded parameter string with the provided options */
- (NSString *)URLEncodedStringValueWithOptions:(TNLURLEncodingOptions)options;
/**
 Return a copy of the dictionary represenation of the parameter collection
 @warning could contain objects that are not encodable!
 */
- (NSDictionary<NSString *, id> *)underlyingDictionaryValue;
/**
 Return a dictionary representation that is directly encodable (no unexpected objects)
 @throw `NSInvalidArgumentException` when an underlying value is not encodable AND
 `TNLURLEncodableDictionaryOptionIgnoreUnsupportedValues` or
 `TNLURLEncodableDictionaryOptionTreatUnsupportedValuesAsEmpty` are not provided as part of the _options_
 */
- (NSDictionary<NSString *, id> *)encodableDictionaryValueWithOptions:(TNLURLEncodableDictionaryOptions)options;
/**
 Return a dictionary representation that is directly encodable (no unexpected objects),
 traversing through arrays and dictionaries recursively to ensure each object is encodable.
 The same as calling `[TNLParameterCollection encodableDictionaryValueWithOptions:TNLURLEncodableDictionaryOptionReplaceArraysWithArraysOfEncodableStrings | TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings]`
 @throw `NSInvalidArgumentException` when an underlying value is not encodable
 */
- (NSDictionary<NSString *, id> *)encodableDictionaryValue;

#pragma mark Convenience Class Methods

/**
 Convenience class method to build a string from `TNLParameterCollection` objects

 @param parameterStringCollection The collection representing the parameter string (can be `nil`)
 @param queryCollection           The collection representing the query (can be `nil`)
 @param fragmentCollection        The collection representing the fragment (can be `nil`)
 @param options                   The options to serialize with

 @return A new string with the appropriate delimeter for each segement present.
 */
+ (NSString *)stringByCombiningParameterString:(nullable TNLParameterCollection *)parameterStringCollection
                                         query:(nullable TNLParameterCollection *)queryCollection
                                      fragment:(nullable TNLParameterCollection *)fragmentCollection
                                       options:(TNLURLEncodingOptions)options;

@end

/**
 Mutable subclass of `TNLParameterCollection`
 */
@interface TNLMutableParameterCollection : TNLParameterCollection

/** Init with a specified hint to the capacity this collection should contain */
- (instancetype)initWithCapacity:(NSUInteger)capacity NS_DESIGNATED_INITIALIZER;

/** init with another `TNLParameterCollection` */
- (instancetype)initWithParameterCollection:(nullable TNLParameterCollection *)otherCollection NS_DESIGNATED_INITIALIZER;

#pragma mark Base Methods

/**
 Set the parameter value
 @param value The value to set.  `nil` will remove the value for the specified _key_.
 If _value_ responds to `copyWithZone:` (aka `NSCopying`), the `copy` will be stored instead of the
 _value_ itself to preserve immutability of parameters.
 @param key   The key to use.
 @note _key_ must be `NSString` objects with length greater than `0`, otherwise an exception will be thrown.
 */
- (void)setParameterValue:(nullable id)value forKey:(NSString *)key;

#pragma mark Add Params Methods

/**
 Parse the parameters from the given _params_ and add them to the collection.
 @note if there are multiple instances of a key, the presence of
 `TNLURLDecodingOptionCombineRepeatingKeysIntoArray` will affect if the parameters are combined into
 an `NSArray` or not.
 @param params String to parse.
 @param options The options to use when parsing.
 */
- (void)addParametersWithURLEncodedString:(nullable NSString *)params
                                  options:(TNLURLDecodingOptions)options;
/** See `addParametersWithURLEncodedString:options:` */
- (void)addParametersWithURLEncodedString:(nullable NSString *)params;

/**
 Add the parameters from the given _dictionary_.
 Setting/adding a dictionary to a parameter collection is ambiguous because it have have many ways
 of being represented.  This method takes a `mode` in order to have the way to format the keys and
 values explicitely provided.
 @param dictionary keys and values to add.  For each value, if the value responds to `copyWithZone:` (aka `NSCopying`), the copy will be stored.
 @param mode The `TNLParameterCollectionAddParametersFromDictionaryMode` to format the keys and values from _dictionary_ into the parameter collection.
 @param combine whether or not to combine two keys that are the same (aka repeat) into an `NSArray` of values
 @note If any key is not an `NSString` an exception will be thrown.
 @note Defaults are used for `TNLParameterCollectionAddParametersFromDictionaryModeURLEncoded`...
 if you want to use something non-default, it is best to URL encode the dictionary yourself first.
 */
- (void)addParametersFromDictionary:(nullable NSDictionary<NSString *,id> *)dictionary
                 withFormattingMode:(TNLParameterCollectionAddParametersFromDictionaryMode)mode
               combineRepeatingKeys:(BOOL)combine
                             forKey:(NSString *)key;
/**
 Same as `addParametersFromDictionary:withFormattingMode:combineRepeatingKeys:forKey:`
 with _mode_ of `TNLParameterCollectionAddParametersFromDictionaryModeUseKeysDirectly` and _key_ ignored.
 */
- (void)addParametersDirectlyFromDictionary:(nullable NSDictionary<NSString *,id> *)dictionary
                       combineRepeatingKeys:(BOOL)combine;

/**
 Add the parameters from the given _params_.
 @param params values to add.  Takes the `underlyingDictionaryValue` of _params_ and calls `addParametersFromDictionary:combineRepeatingKeys:`
 @param combine whether to combine repeating keys into an `NSArray`
 @note If any key is not an `NSString` and exception will be thrown.
 */
- (void)addParametersFromParameterCollection:(nullable TNLParameterCollection *)params
                        combineRepeatingKeys:(BOOL)combine;
/** See `addParametersFromParameterCollection:combineRepeatingKeys:` (where _combine_ is `NO`) */
- (void)addParametersFromParameterCollection:(nullable TNLParameterCollection *)params;

/**
 Parse the parameters from the given _URL_ filtering on the desired _types_.
 @note if there are multiple instances of a key, the presence of
 `TNLURLDecodingOptionCombineRepeatingKeysIntoArray` will affect if the parameters are combined into
 an `NSArray` or not.
 @param URL   The `NSURL` to parse
 @param types which types to parse.  Commonly, REST APIs will just use the __query__ type.
 @param options The options to use when parsing.
 */
- (void)addParametersFromURL:(nullable NSURL *)URL
       parsingParameterTypes:(TNLParameterTypes)types
                     options:(TNLURLDecodingOptions)options;
/** See `addParametersFromURL:parsingParameterTypes:options:` */
- (void)addParametersFromURL:(nullable NSURL *)URL
       parsingParameterTypes:(TNLParameterTypes)types;

/** Remove all parameters */
- (void)removeAllParameters;

@end

/**
 Convenience category for retrieving the `TNLParameterCollection` objects from an `NSURL` via its
 `parameterString`, `query` and `fragment` accessors.
 */
@interface NSURL (Parameters)

/** `TNLParameterCollection` from `[NSURL parameterString]` */
- (TNLParameterCollection *)tnl_parameterStringCollectionWithOptions:(TNLURLDecodingOptions)options;
/** See `tnl_parameterStringCollectionWithOptions:` */
- (TNLParameterCollection *)tnl_parameterStringCollection;

/** `TNLParameterCollection` from `[NSURL query]` */
- (TNLParameterCollection *)tnl_queryCollectionWithOptions:(TNLURLDecodingOptions)options;
/** See `tnl_queryCollectionWithOptions:` */
- (TNLParameterCollection *)tnl_queryCollection;

/** `TNLParameterCollection` from `[NSURL fragment]` */
- (TNLParameterCollection *)tnl_fragmentCollectionWithOptions:(TNLURLDecodingOptions)options;
/** See `tnl_fragmentCollectionWithOptions:` */
- (TNLParameterCollection *)tnl_fragmentCollection;

@end

/**
 # TNLParameterCollection (KeyedSubscripting)

 `TNLParameterCollection` supports keyed subscripting
 */
@interface TNLParameterCollection (KeyedSubscripting)

/**
 `id obj = collection[key]`
 @param key The key to look up.  Must be an `NSString`.
 @return the value matching the _key_.  If not found, returns `nil`.
 */
- (nullable id)objectForKeyedSubscript:(NSString *)key; // key must be NSString

@end

/**
 # TNLMutableParameterCollection (KeyedSubscripting)

 `TNLMutableParameterCollection` supports keyed subscripting
 */
@interface TNLMutableParameterCollection (KeyedSubscripting)

/**
 `collection[key] = obj;`
 @param obj The object to set.  `nil` will remove the value for the specified _key_.
 @param key The key to use.  Must be an `NSString`.
 __See Also:__ `setParameterValue:forKey:`
 */
- (void)setObject:(nullable id)obj forKeyedSubscript:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

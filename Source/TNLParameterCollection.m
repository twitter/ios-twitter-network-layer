//
//  TNLParameterCollection.m
//  TwitterNetworkLayer
//
//  Created on 10/24/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLParameterCollection.h"
#import "TNLURLCoding.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const kParametersCodingKey = @"parameters";

typedef NSString *(^TNLParameterCollectionUpdateKeysAndValuesIterativeKeyBlock)(NSString *key, id obj);

@interface TNLParameterCollection ()

@property (nonatomic, readonly) NSDictionary *parameters;

- (instancetype)initWithDirectlyAssignedDictionary:(nullable NSDictionary<NSString *, id> *)dict;

@end

@implementation TNLParameterCollection
{
    @protected
    NSDictionary<NSString *, id> *_parameters;
}

@synthesize parameters = _parameters;

- (instancetype)init
{
    return [super init];
}

- (instancetype)initWithDirectlyAssignedDictionary:(nullable NSDictionary<NSString *, id> *)dict
{
    if (self = [self init]) {
        _parameters = dict; // don't copy!
    }
    return self;
}

- (instancetype)initWithURLEncodedString:(nullable NSString *)params
{
    return [self initWithURLEncodedString:params options:TNLURLDecodingOptionsNone];
}

- (instancetype)initWithURLEncodedString:(nullable NSString *)params
                                 options:(TNLURLDecodingOptions)options
{
    TNLMutableParameterCollection *mCollection = [[TNLMutableParameterCollection alloc] initWithURLEncodedString:params
                                                                                                         options:options];
    return [self initWithParameterCollection:mCollection];
}

- (instancetype)initWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary
{
    TNLMutableParameterCollection *mCollection = [[TNLMutableParameterCollection alloc] initWithDictionary:dictionary];
    return [self initWithParameterCollection:mCollection];
}

- (instancetype)initWithURL:(nullable NSURL *)URL
      parsingParameterTypes:(TNLParameterTypes)types
{
    return [self initWithURL:URL
       parsingParameterTypes:types
                     options:TNLURLDecodingOptionsNone];
}

- (instancetype)initWithURL:(nullable NSURL *)URL
      parsingParameterTypes:(TNLParameterTypes)types
                    options:(TNLURLDecodingOptions)options
{
    TNLMutableParameterCollection *mCollection = [[TNLMutableParameterCollection alloc] initWithURL:URL
                                                                              parsingParameterTypes:types
                                                                                            options:options];
    return [self initWithParameterCollection:mCollection];
}

- (instancetype)initWithParameterCollection:(nullable TNLParameterCollection *)otherCollection
{
    if (self = [super init]) {
        _parameters = [otherCollection.parameters copy];
    }
    return self;
}

#pragma mark NSMutableCopying

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    return [[TNLMutableParameterCollection alloc] initWithParameterCollection:self];
}

#pragma mark Count

- (NSUInteger)count
{
    return _parameters.count;
}

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    NSDictionary *d = [aDecoder decodeObjectOfClass:[NSDictionary class]
                                             forKey:kParametersCodingKey];
    return [self initWithDirectlyAssignedDictionary:d];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_parameters forKey:kParametersCodingKey];
}

#pragma mark NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained __nullable [__nonnull])buffer
                                    count:(NSUInteger)len
{
    return [_parameters countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark Keyed Subscripting

- (nullable id)objectForKeyedSubscript:(NSString *)key
{
    return [self parameterValueForKey:key];
}

#pragma mark Access

- (nullable id)parameterValueForKey:(NSString *)key
{
    return _parameters[key];
}

#pragma mark Helpers

- (NSArray *)allKeys
{
    return _parameters.allKeys;
}

- (void)enumerateParameterKeysAndValuesUsingBlock:(void (^)(NSString *, id, BOOL *))block
{
    [_parameters enumerateKeysAndObjectsUsingBlock:block];
}

- (void)enumerateParameterKeysAndValuesWithOptions:(NSEnumerationOptions)opts
                                        usingBlock:(void (^)(NSString *, id, BOOL *))block
{
    [_parameters enumerateKeysAndObjectsWithOptions:opts usingBlock:block];
}

#pragma mark URL Params

- (NSString *)URLEncodedStringValue
{
    return [self URLEncodedStringValueWithOptions:TNLURLEncodingOptionsNone];
}

- (NSString *)stableURLEncodedStringValue
{
    return [self URLEncodedStringValueWithOptions:TNLURLEncodingOptionStableOrder];
}

- (NSDictionary<NSString *, id> *)underlyingDictionaryValue
{
    return [_parameters copy];
}

- (NSDictionary<NSString *, id> *)encodableDictionaryValue
{
    const TNLURLEncodableDictionaryOptions options = TNLURLEncodableDictionaryOptionReplaceArraysWithArraysOfEncodableStrings |
                                                     TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings;
    return [self encodableDictionaryValueWithOptions:options];
}

- (NSDictionary<NSString *, id> *)encodableDictionaryValueWithOptions:(TNLURLEncodableDictionaryOptions)options
{
    return TNLURLEncodableDictionary(_parameters, options);
}

+ (NSString *)stringByCombiningParameterString:(nullable TNLParameterCollection *)parameterStringCollection
                                         query:(nullable TNLParameterCollection *)queryCollection
                                      fragment:(nullable TNLParameterCollection *)fragmentCollection
                                       options:(TNLURLEncodingOptions)options
{
    NSString *parameterString;
    NSString *query;
    NSString *fragment;

    if (parameterStringCollection) {
        parameterString = [parameterStringCollection URLEncodedStringValueWithOptions:options];
        TNLAssert(parameterString);
    }
    if (queryCollection) {
        query = [queryCollection URLEncodedStringValueWithOptions:options];
        TNLAssert(query);
    }
    if (fragmentCollection) {
        fragment = [fragmentCollection URLEncodedStringValueWithOptions:options];
        TNLAssert(fragment);
    }

    NSMutableString *string = [NSMutableString string];

    if (parameterString.length > 0) {
        [string appendString:@";"];
        [string appendString:parameterString];
    }
    if (query.length > 0) {
        [string appendString:@"?"];
        [string appendString:query];
    }
    if (fragment.length > 0) {
        [string appendString:@"#"];
        [string appendString:fragment];
    }

    return string;
}

- (NSString *)URLEncodedStringValueWithOptions:(TNLURLEncodingOptions)options
{
    return TNLURLEncodeDictionary(_parameters, options);
}

#pragma mark Description

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p: %@='%@'>", NSStringFromClass([self class]), self, NSStringFromSelector(@selector(URLEncodedStringValue)), [self URLEncodedStringValueWithOptions:TNLURLEncodingOptionsNone | TNLURLEncodingOptionTreatUnsupportedValuesAsEmpty]];
}

#pragma mark Equivalence

- (NSUInteger)hash
{
    return _parameters.hash;
}

- (BOOL)isEqual:(id)object
{
    if ([super isEqual:object]) {
        return YES;
    }

    if ([object isKindOfClass:[TNLParameterCollection class]]) {
        return [_parameters isEqualToDictionary:((TNLParameterCollection *)object)->_parameters];
    }

    return NO;
}

@end

@implementation TNLMutableParameterCollection

- (instancetype)init
{
    return [self initWithCapacity:0];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity
{
    if (self = [super init]) {
        _parameters = capacity ? [[NSMutableDictionary alloc] initWithCapacity:capacity] : [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (instancetype)initWithURLEncodedString:(nullable NSString *)params
                                 options:(TNLURLDecodingOptions)options
{
    if (self = [self init]) {
        [self addParametersWithURLEncodedString:params options:options];
    }
    return self;
}

- (instancetype)initWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary
{
    if (self = [self initWithCapacity:dictionary.count]) {
        _addParametersDirectly(self, dictionary, NO /*combineRepeatingKeys*/);
    }
    return self;
}

- (instancetype)initWithURL:(nullable NSURL *)URL
      parsingParameterTypes:(TNLParameterTypes)types
                    options:(TNLURLDecodingOptions)options
{
    if (self = [self init]) {
        [self addParametersFromURL:URL parsingParameterTypes:types options:options];
    }
    return self;
}

- (instancetype)initWithParameterCollection:(nullable TNLParameterCollection *)otherCollection
{
    if (self = [super init]) {
        _parameters = [[NSMutableDictionary alloc] initWithDictionary:otherCollection.parameters];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    NSDictionary *d = [aDecoder decodeObjectOfClass:[NSMutableDictionary class]
                                             forKey:kParametersCodingKey];
    if (!d) {
        d = [[NSMutableDictionary alloc] init];
    }
    return [self initWithDirectlyAssignedDictionary:d];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return [[TNLParameterCollection alloc] initWithParameterCollection:self];
}

- (void)addParametersWithURLEncodedString:(nullable NSString *)params
{
    [self addParametersWithURLEncodedString:params options:TNLURLDecodingOptionsNone];
}

- (void)addParametersWithURLEncodedString:(nullable NSString *)params
                                  options:(TNLURLDecodingOptions)options
{
    const BOOL combine = TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLURLDecodingOptionCombineRepeatingKeysIntoArray);
    _addParametersDirectly(self,
                           TNLURLDecodeDictionary(params, options),
                           combine);
}

- (void)addParametersFromURL:(nullable NSURL *)URL parsingParameterTypes:(TNLParameterTypes)types
{
    [self addParametersFromURL:URL
         parsingParameterTypes:types
                       options:TNLURLDecodingOptionsNone];
}

- (void)addParametersFromURL:(nullable NSURL *)URL
       parsingParameterTypes:(TNLParameterTypes)types
                     options:(TNLURLDecodingOptions)options
{
    if (TNL_BITMASK_HAS_SUBSET_FLAGS(types, TNLParameterTypeURLParameterString)) {
        NSString *parameterString;
        if (tnl_available_ios_13) {
            // parameter string is no longer considered valid according to Apple, which is wise
            // ... but we'll still support parsing it
            NSString *path = URL.path;
            if (path) {
                NSRange range = [path rangeOfString:@";"];
                if (range.location != NSNotFound) {
                    parameterString = [path substringFromIndex:range.location + 1];
                }
            }
#if !TARGET_OS_UIKITFORMAC
        } else {
            parameterString = URL.parameterString;
#endif
        }
        [self addParametersWithURLEncodedString:parameterString options:options];
    }
    if (TNL_BITMASK_HAS_SUBSET_FLAGS(types, TNLParameterTypeURLQuery)) {
        [self addParametersWithURLEncodedString:URL.query options:options];
    }
    if (TNL_BITMASK_HAS_SUBSET_FLAGS(types, TNLParameterTypeURLFragment)) {
        [self addParametersWithURLEncodedString:URL.fragment options:options];
    }
}

- (void)addParametersDirectlyFromDictionary:(nullable NSDictionary<NSString *,id> *)dictionary
                       combineRepeatingKeys:(BOOL)combine
{
    _addParametersDirectly(self, dictionary, combine);
}

- (void)addParametersFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary
                 withFormattingMode:(TNLParameterCollectionAddParametersFromDictionaryMode)mode
               combineRepeatingKeys:(BOOL)combine
                             forKey:(NSString *)key
{
    if (!dictionary) {
        return;
    }

    switch (mode) {
        case TNLParameterCollectionAddParametersFromDictionaryModeUseKeysDirectly:
            _addParametersDirectly(self, dictionary, combine);
            return;
        case TNLParameterCollectionAddParametersFromDictionaryModeURLEncoded:
            _addParametersUsingURLEncoding(self, dictionary, combine, key);
            return;
        case TNLParameterCollectionAddParametersFromDictionaryModeJSONEncoded:
            _addParametersUsingJSONEncoding(self, dictionary, combine, key);
            return;
        case TNLParameterCollectionAddParametersFromDictionaryModeDotSyntaxOnProvidedKey:
            _addParametersUsingDotSyntax(self, dictionary, combine, key);
            return;
    }

    TNLAssertNever();
}

static void _setObject(PRIVATE_SELF(TNLMutableParameterCollection),
                       id obj,
                       NSString *key,
                       BOOL combineRepeatingKeys)
{
    if (!self) {
        return;
    }

    if (combineRepeatingKeys) {
        id oldValue = self->_parameters[key];
        if ([oldValue isKindOfClass:[NSString class]]) {
            obj = @[ oldValue, obj ];
        } else if ([oldValue isKindOfClass:[NSArray class]]) {
            oldValue = [oldValue mutableCopy];
            [(NSMutableArray *)oldValue addObject:obj];
            obj = oldValue;
        }
    }

    self[key] = obj;
}

static void _updateWithDictionary(PRIVATE_SELF(TNLMutableParameterCollection),
                                  NSDictionary<NSString *, id> * __nullable dictionary,
                                  BOOL combineRepeatingKeys,
                                  TNLParameterCollectionUpdateKeysAndValuesIterativeKeyBlock iterativeKeyBlock)
{
    if (!self) {
        return;
    }

    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:@"keys must be NSStrings for TNLParameterCollection"
                                         userInfo:@{ @"key" : key, @"value" : obj }];
        }
        if ([obj respondsToSelector:@selector(copyWithZone:)]) {
            obj = [obj copy];
            TNLAssert(obj != nil);
        }

        NSString *newKey = iterativeKeyBlock(key, obj);
        TNLAssert(newKey != nil);

        _setObject(self, obj, newKey, combineRepeatingKeys);
    }];
}

static void _addParametersDirectly(PRIVATE_SELF(TNLMutableParameterCollection),
                                   NSDictionary<NSString *, id> * __nullable dictionary,
                                   BOOL combineRepeatingKeys)
{
    if (!self) {
        return;
    }

    _updateWithDictionary(self,
                          dictionary,
                          combineRepeatingKeys,
                          ^NSString *(NSString *key, id obj) {
        return key;
    });
}

static void _addParametersUsingURLEncoding(PRIVATE_SELF(TNLMutableParameterCollection),
                                           NSDictionary<NSString *, id> * __nullable dictionary,
                                           BOOL combineRepeatingKeys,
                                           NSString *key)
{
    if (!self) {
        return;
    }

    dictionary = TNLURLEncodableDictionary(dictionary, TNLURLEncodableDictionaryOptionReplaceArraysWithArraysOfEncodableStrings | TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings);
    NSString *obj = TNLURLEncodeDictionary(dictionary, TNLURLEncodingOptionStableOrder);
    _setObject(self, obj, key, combineRepeatingKeys);
}

static void _addParametersUsingJSONEncoding(PRIVATE_SELF(TNLMutableParameterCollection),
                                            NSDictionary<NSString *, id> * __nullable dictionary,
                                            BOOL combineRepeatingKeys,
                                            NSString *key)
{
    if (!self) {
        return;
    }

    dictionary = TNLURLEncodableDictionary(dictionary, TNLURLEncodableDictionaryOptionReplaceArraysWithArraysOfEncodableStrings | TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings);
    NSJSONWritingOptions options = 0;
    if (tnl_available_ios_11) {
        options = NSJSONWritingSortedKeys;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary
                                                   options:options
                                                     error:NULL];
    NSString *json = [[NSString alloc] initWithData:data
                                           encoding:NSUTF8StringEncoding];
    _setObject(self, json, key, combineRepeatingKeys);
}

static void _addParametersUsingDotSyntax(PRIVATE_SELF(TNLMutableParameterCollection),
                                         NSDictionary<NSString *, id> * __nullable dictionary,
                                         BOOL combineRepeatingKeys,
                                         NSString *dictionaryKey)
{
    if (!self) {
        return;
    }

    _updateWithDictionary(self,
                          dictionary,
                          combineRepeatingKeys,
                          ^NSString *(NSString * _Nonnull key, id  _Nonnull obj) {
        return [NSString stringWithFormat:@"%@.%@", dictionaryKey, key];
    });
}

- (void)addParametersFromParameterCollection:(nullable TNLParameterCollection *)params
                        combineRepeatingKeys:(BOOL)combine
{
    _addParametersDirectly(self, params.underlyingDictionaryValue, combine);
}

- (void)addParametersFromParameterCollection:(nullable TNLParameterCollection *)params
{
    [self addParametersFromParameterCollection:params combineRepeatingKeys:NO];
}

- (void)setObject:(nullable id)obj forKeyedSubscript:(NSString *)key
{
    [self setParameterValue:obj forKey:(NSString *)key];
}

- (void)setParameterValue:(nullable id)obj forKey:(NSString *)key
{
    if (!obj) {
        [((NSMutableDictionary *)_parameters) removeObjectForKey:key];
        return;
    }

    if (![key isKindOfClass:[NSString class]]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"keys must be NSStrings for TNLParameterCollection"
                                     userInfo:@{ @"key" : key ?: [NSNull null], @"value" : obj }];
    } else if (key.length == 0) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"keys cannot be empty strings for TNLParameterCollection"
                                     userInfo:@{ @"key" : key, @"value" : obj }];
    }

    if ([obj respondsToSelector:@selector(copyWithZone:)]) {
        obj = [obj copy];
        TNLAssert(obj != nil);
    }
    ((NSMutableDictionary *)_parameters)[key] = obj;
}

- (void)removeAllParameters
{
    [(NSMutableDictionary *)_parameters removeAllObjects];
}

@end

@implementation NSURL (Parameters)

- (TNLParameterCollection *)tnl_parameterStringCollection
{
    return [self tnl_parameterStringCollectionWithOptions:TNLURLDecodingOptionsNone];
}

- (TNLParameterCollection *)tnl_parameterStringCollectionWithOptions:(TNLURLDecodingOptions)options
{
    return [[TNLParameterCollection alloc] initWithURL:self
                                 parsingParameterTypes:TNLParameterTypeURLParameterString
                                               options:options];
}

- (TNLParameterCollection *)tnl_queryCollection
{
    return [self tnl_queryCollectionWithOptions:TNLURLDecodingOptionsNone];
}

- (TNLParameterCollection *)tnl_queryCollectionWithOptions:(TNLURLDecodingOptions)options
{
    return [[TNLParameterCollection alloc] initWithURL:self
                                 parsingParameterTypes:TNLParameterTypeURLQuery
                                               options:options];
}

- (TNLParameterCollection *)tnl_fragmentCollection
{
    return [self tnl_fragmentCollectionWithOptions:TNLURLDecodingOptionsNone];
}

- (TNLParameterCollection *)tnl_fragmentCollectionWithOptions:(TNLURLDecodingOptions)options
{
    return [[TNLParameterCollection alloc] initWithURL:self
                                 parsingParameterTypes:TNLParameterTypeURLFragment
                                               options:options];
}

@end

NS_ASSUME_NONNULL_END

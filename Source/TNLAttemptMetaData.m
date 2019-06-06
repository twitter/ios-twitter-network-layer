//
//  TNLAttemptMetaData.m
//  TwitterNetworkLayer
//
//  Created on 1/16/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "TNLAttemptMetaData_Project.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * const kMetaDataDictionaryKey = @"metaDataDictionary";
static NSString * const kFinalKey = @"final";

@interface TNLAttemptMetaData ()
{
    NSDictionary *_metaDataDictionary;
    BOOL _final;
}
@end

@implementation TNLAttemptMetaData

- (instancetype)initWithMetaDataDictionary:(nullable NSDictionary<NSString *, id> *)dictionary
{
    if (self = [super init]) {
        _final = NO;
        _metaDataDictionary = [dictionary mutableCopy] ?: [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)init
{
    return [self initWithMetaDataDictionary:nil];
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init]) {
        _final = [aDecoder decodeBoolForKey:kFinalKey];
        NSDictionary *metaDataDictionary = [aDecoder decodeObjectOfClass:[NSDictionary class]
                                                                  forKey:kMetaDataDictionaryKey];
        _metaDataDictionary = (_final) ? [metaDataDictionary copy] : [metaDataDictionary mutableCopy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[_metaDataDictionary copy] forKey:kMetaDataDictionaryKey];
    [aCoder encodeBool:_final forKey:kFinalKey];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (NSUInteger)hash
{
    return _metaDataDictionary.hash;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }

    if ([object isKindOfClass:[TNLAttemptMetaData class]]) {
        return [_metaDataDictionary isEqualToDictionary:[object metaDataDictionary]];
    }

    return NO;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p: %@>", NSStringFromClass([self class]), self, _metaDataDictionary];
}

- (NSDictionary *)metaDataDictionary
{
    return _metaDataDictionary;
}

- (void)finalizeMetaData
{
    if (_final) {
        return;
    }

    _final = YES;
    _metaDataDictionary = [_metaDataDictionary copy];
}

@end

// Helper macros for coding & printing object; saves us from key & value name typos.

#define OBJECT_FIELD(field, fieldUpper, type) \
- (nullable type *)field \
{ \
    return _metaDataDictionary[@#field]; \
} \
- (void)set##fieldUpper:(nullable type *)field \
{ \
    if (field == nil) { \
        [(NSMutableDictionary *)_metaDataDictionary removeObjectForKey:@#field]; \
    } else { \
        ((NSMutableDictionary *)_metaDataDictionary)[@#field] = [field copy]; \
    } \
} \
- (BOOL)has##fieldUpper \
{ \
    return _metaDataDictionary[@#field] != nil; \
} \

#define PRIMITIVE_FIELD(field, fieldUpper, type, getter) \
- (type)field \
{ \
    return [_metaDataDictionary[@#field] getter]; \
} \
- (void)set##fieldUpper:(type)field \
{ \
    ((NSMutableDictionary *)_metaDataDictionary)[@#field] = @(field); \
} \
- (BOOL)has##fieldUpper \
{ \
    return _metaDataDictionary[@#field] != nil; \
} \

@implementation TNLAttemptMetaData (HTTP)
// See TNLAttemptMetadata_Project.h for list of fields.
HTTP_FIELDS()
@end

#undef OBJECT_FIELD
#undef PRIMITIVE_FIELD

NS_ASSUME_NONNULL_END

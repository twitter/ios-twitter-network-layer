//
//  NSDictionary+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 8/24/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "NSDictionary+TNLAdditions.h"
#import "TNL_Project.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSDictionary (TNLAdditions)

- (nullable NSSet *)tnl_keysMatchingCaseInsensitiveKey:(NSString *)key
{
    NSMutableSet *keys = nil;
    TNLAssert([key isKindOfClass:[NSString class]]);
    if ([key isKindOfClass:[NSString class]]) {
        for (NSString *otherKey in self.allKeys) {
            TNLAssert([otherKey isKindOfClass:[NSString class]]);
            if ([otherKey caseInsensitiveCompare:key] == NSOrderedSame) { // TWITTER_STYLE_CASE_INSENSITIVE_COMPARE_NIL_PRECHECKED
                if (!keys) {
                    keys = [NSMutableSet set];
                }
                [keys addObject:otherKey];
            }
        }
    }
    return keys;
}

- (nullable NSArray *)tnl_objectsForCaseInsensitiveKey:(NSString *)key
{
    TNLAssert(key);
    NSSet *keys = [self tnl_keysMatchingCaseInsensitiveKey:key];
    NSMutableArray *objects = (keys.count > 0) ? [NSMutableArray array] : nil;
    for (NSString *otherKey in keys) {
        [objects addObject:self[otherKey]];
    }
    return objects;
}

- (nullable id)tnl_objectForCaseInsensitiveKey:(NSString *)key
{
    id value = [self objectForKey:key];
    if (!value) {
        for (NSString *innerKey in self.allKeys) {
            if ([innerKey isKindOfClass:[NSString class]]) {
                if ([innerKey caseInsensitiveCompare:key] == NSOrderedSame) { // TWITTER_STYLE_CASE_INSENSITIVE_COMPARE_NIL_PRECHECKED
                    value = [self objectForKey:innerKey];
                    break;
                }
            }
        }
    }
    return value;
}

- (id)tnl_copyWithLowercaseKeys
{
    return [self tnl_copyToMutable:NO uppercase:NO];
}

- (id)tnl_copyWithUppercaseKeys
{
    return [self tnl_copyToMutable:NO uppercase:YES];
}

- (id)tnl_mutableCopyWithLowercaseKeys
{
    return [self tnl_copyToMutable:YES uppercase:NO];
}

- (id)tnl_mutableCopyWithUppercaseKeys
{
    return [self tnl_copyToMutable:YES uppercase:YES];
}

- (id)tnl_copyToMutable:(BOOL)mutable uppercase:(BOOL)uppercase
{
    NSMutableDictionary *replacementDict = nil;

    for (NSString *key in self) {
        NSString *updatedKey = uppercase ? [key uppercaseString] : [key lowercaseString];
        if (![key isEqualToString:updatedKey]) {
            if (!replacementDict) {
                replacementDict = [self mutableCopy];
            }

            [replacementDict removeObjectForKey:key];
            replacementDict[updatedKey] = self[key];
        }
    }

    return replacementDict ?: (mutable ? [self mutableCopy] : [self copy]);
}

@end

@implementation NSMutableDictionary (TNLAdditions)

- (void)tnl_removeObjectsForCaseInsensitiveKey:(NSString *)key
{
    TNLAssert(key);
    NSArray *keys = [[self tnl_keysMatchingCaseInsensitiveKey:key] allObjects];
    if (keys) {
        [self removeObjectsForKeys:keys];
    }
}

- (void)tnl_setObject:(id)object forCaseInsensitiveKey:(NSString *)key
{
    TNLAssert(key);
    [self tnl_removeObjectsForCaseInsensitiveKey:key];
#ifndef __clang_analyzer__ // reports key can be nil nil; we prefer to crash if it is
    self[key] = object;
#endif
}

- (void)tnl_makeAllKeysLowercase
{
    NSDictionary *d = [self tnl_mutableCopyWithLowercaseKeys];
    [self removeAllObjects];
    [self addEntriesFromDictionary:d];
}

- (void)tnl_makeAllKeysUppercase
{
    NSDictionary *d = [self tnl_mutableCopyWithUppercaseKeys];
    [self removeAllObjects];
    [self addEntriesFromDictionary:d];
}

@end

NS_ASSUME_NONNULL_END


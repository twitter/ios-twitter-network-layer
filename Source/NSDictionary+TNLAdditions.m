//
//  NSDictionary+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created on 8/24/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
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
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    for (NSString *key in self) {
        d[(uppercase) ? key.uppercaseString : key.lowercaseString] = self[key];
    }
    return (mutable) ? d : [d copy];
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


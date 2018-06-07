//
//  NSDictionary+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 8/24/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Additional methods for `NSDictionary`
 See also `NSMutableDictionary(TNLAdditions)`
 */
@interface NSDictionary (TNLAdditions)

/**
 Retrieve all objects who's keys match the provided case-insensitive key.
 @param key the key to lookup
 @return an array of matching objects or `nil` if none is found.
 @note the cost of using this method vs objectForKey: is O(n) vs O(1)
 */
- (nullable NSArray *)tnl_objectsForCaseInsensitiveKey:(NSString *)key;

/**
 Find all keys in the receiver that match the given case-insensitive `key`
 @param key the key to lookup
 @return a set of the matching keys if found, otherwise `nil`
 @note this method runs in O(n) time
 */
- (nullable NSSet<NSString *> *)tnl_keysMatchingCaseInsensitiveKey:(NSString *)key;

/**
 Make an immutable copy with all keys being lowercase
 @return an NSDictionary
 */
- (id)tnl_copyWithLowercaseKeys;

/**
 Make an immutable copy with all keys being uppercase
 @return an NSDictionary
 */
- (id)tnl_copyWithUppercaseKeys;

/**
 Make a mutable copy with all keys being lowercase
 @return an NSMutableDictionary
 */
- (id)tnl_mutableCopyWithLowercaseKeys;

/**
 Make a mutable copy with all keys being uppercase
 @return an NSMutableDictionary
 */
- (id)tnl_mutableCopyWithUppercaseKeys;

@end

/**
 Additional methods for `NSMutableDictionary`
 See also `NSDictionary(TNLAdditions)`
 */
@interface NSMutableDictionary (TNLAdditions)

/**
 Remove all objects matching the provided case-insensitive 'key'
 @param key the key to match against
 @note the cost of using this method vs removeObjectForKey: is O(n) vs O(1)
 */
- (void)tnl_removeObjectsForCaseInsensitiveKey:(NSString *)key;

/**
 Set an object for a given 'key'.  Any existing key-value-pairs that match the provided
 key (case-insensitive) will be removed.
 @param object the object to set
 @param key the key to associate with the object
 @note the cost of using this method vs setObject:forKey: is O(n) vs O(1)
 */
- (void)tnl_setObject:(id)object forCaseInsensitiveKey:(NSString *)key;

/**
 Make all keys lowercase
 */
- (void)tnl_makeAllKeysLowercase;

/**
 Make all keys uppercase
 */
- (void)tnl_makeAllKeysUppercase;

@end

NS_ASSUME_NONNULL_END


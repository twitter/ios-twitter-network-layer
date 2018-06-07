//
//  TNLLRUCache.h
//  TwitterNetworkLayer
//
//  Created on 10/27/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TNLLRUCacheDelegate;
@protocol TNLLRUEntry;

NS_ASSUME_NONNULL_BEGIN

/**
 `TNLLRUCache` is a collection object that maintains a set of `TNLLRUEntry` objects.
 You can look up an entry by identifier in constant time and it maintains the entries so that you
 can remove the least-recently-used (LRU) entry.

 @warning This class is exposed as a convenience to consumers that might be able to take advantage
 of an LRU collection.
 It is not permanent though and may eventually move to a shared core utilities library that TNL
 will depend on.
 It is recommended to NOT use this class unless you are prepared to migrate to a shared core
 utilities library if one is created.
 */
@interface TNLLRUCache : NSObject <NSFastEnumeration>

/** Optional delegate */
@property (nonatomic, weak, nullable) id<TNLLRUCacheDelegate> delegate;

/**
 The head entry of the cache, most recently used entry.
 `nil` if the cache is empty.
 Accessing does not mutate this LRU cache.
 */
@property (nonatomic, readonly, nullable) id<TNLLRUEntry> headEntry;

/**
 The tail entry of the cache, least recently used entry.
 `nil` if the cache is empty.
 Accessing does not mutate this LRU cache.
 */
@property (nonatomic, readonly, nullable) id<TNLLRUEntry> tailEntry;

/** the number of entries in the manfiest.  Execution time is constant, O(1) */
- (NSUInteger)numberOfEntries;

/** designted initializer */
- (instancetype)initWithEntries:(nullable NSArray<id<TNLLRUEntry>> *)arrayOfLRUEntries
                       delegate:(nullable id<TNLLRUCacheDelegate>)delegate NS_DESIGNATED_INITIALIZER;

/**
 Access an entry by identifier.
 If entry is found, it is moved to head if _canMutate_ is `YES` and the entry's
 `shouldAccessMoveLRUEntryToHead` value is `YES`.
 Returns `nil` if no entry was found.
 Execution time is constant, O(1)
 */
- (nullable id<TNLLRUEntry>)entryWithIdentifier:(NSString *)identifier canMutate:(BOOL)moveToHead;

/**
 Same as `entryWithIdentifier:canMutate:` with _canMutate being `YES`
 */
- (nullable id<TNLLRUEntry>)entryWithIdentifier:(NSString *)identifier;

/**
 Copy all entries as an `NSArray` (does not count as an access that would affect order in LRU cache).
 Execution time is linear, O(n)
 */
- (NSArray<id<TNLLRUEntry>> *)allEntries;

/**
 Sets the given _entry_ as the head entry.
 If _entry_ was not in the cache, it is added to the cache.
 If _entry_ was in the cache, it is just moved to the head if
 `[TNLLRUEntry shouldAccessMoveLRUEntryToHead]` returns `YES`.
 Execution time is constant, O(1)
 */
- (void)addEntry:(id<TNLLRUEntry>)entry;

/**
 Adds the given _entry_ as the tail entry.
 Execution time is constant, O(1)

 @note this circumvents the value of the LRU cache, so it is recommended that only `addEntry:` is used.
 Using this method only really makes sense during `TNLLRUCache` set up time and not beyond that.
 */
- (void)appendEntry:(id<TNLLRUEntry>)entry;

/**
 Removes the specified _entry_.
 Execution time is constant, O(1)

 @note This does will trigger the `[TNLLRUCacheDelegate tnl_cache:didEvictEntry:]` callback if then
 entry was in the cache
 */
- (void)removeEntry:(nullable id<TNLLRUEntry>)entry;

/**
 Remove the tail entry (least-recently-used) if the cache is not empty.
 Execution time is constant, O(1)

 @return the entry removed or `nil` if no entry was removed.
 @note This does will trigger the `[TNLLRUCacheDelegate tnl_cache:didEvictEntry:]` callback if an
 entry was removed
 */
- (nullable id<TNLLRUEntry>)removeTailEntry;

/**
 Clear all entries in the cache.
 Execution time is linear, O(n).  This is because each value has to dealloc.

 @note This does NOT trigger the `[TNLLRUCacheDelegate tnl_cache:didEvictEntry:]` callback
 */
- (void)clearAllEntries;

@end

/**
 Delegate protocol for `TNLLRUCache`
 */
@protocol TNLLRUCacheDelegate <NSObject>

@optional
/**
 Optional callback for when a specific _entry_ is evicted from the _cache_.
 @note This method is NOT called on cache `dealloc` nor when `[TNLLRUCache clearAllEntries]` is called.
 */
- (void)tnl_cache:(TNLLRUCache *)cache
    didEvictEntry:(id<TNLLRUEntry>)entry;

/**
 Optional callback to check if a specific _entry_ can be evicted from the _cache_.
 Return `NO` to prevent eviction.
 Default when unimplemented is `YES`.
 Only used in conjuction with `removeTailEntry`.
 */
- (BOOL)tnl_cache:(TNLLRUCache *)cache
    canEvictEntry:(id<TNLLRUEntry>)entry;

@end

/**
 Protocol for `TNLLRUCache` support.
 */
@protocol TNLLRUEntry <NSObject>

@required

/** The unique identifier for the entry */
- (NSString *)LRUEntryIdentifier;

/**
 Return `YES` to update the entry as most-recently-used when it is accessed.
 Otherwise, return `NO`.
 */
- (BOOL)shouldAccessMoveLRUEntryToHead;

/**
 A property to store the strong reference to the next entry.
 This property will be managed by the `TNLLRUManfiest` and should not be manipulated.
 */
@property (nonatomic, nullable) id<TNLLRUEntry> nextLRUEntry;

/**
 A property to store the weak reference to the previous entry.
 This property will be managed by the `TNLLRUManfiest` and should not be manipulated.
 */
@property (nonatomic, nullable, weak) id<TNLLRUEntry> previousLRUEntry;

@end

NS_ASSUME_NONNULL_END


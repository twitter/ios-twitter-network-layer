//
//  TNLLRUCache.m
//  TwitterNetworkLayer
//
//  Created on 10/27/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLLRUCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLLRUCache ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, id<TNLLRUEntry>> *cache;

- (void)clearEntry:(id<TNLLRUEntry>)entry;
- (void)moveEntryToFront:(id<TNLLRUEntry>)entry;

@end

NS_INLINE void TNLLRUCacheAssertHeadAndTail(TNLLRUCache *cache)
{
    if (gTwitterNetworkLayerAssertEnabled) {
        TNLAssert(!cache.headEntry == !cache.tailEntry);
        if (cache.headEntry) {
            TNLAssert(cache.cache[cache.headEntry.LRUEntryIdentifier] == cache.headEntry);
        }
        if (cache.tailEntry) {
            TNLAssert(cache.cache[cache.tailEntry.LRUEntryIdentifier] == cache.tailEntry);
        }
    }
}

@implementation TNLLRUCache
{
    struct {
        BOOL delegateSupportsDidEvictSelector;
        BOOL delegateSupportsCanEvictSelector;
    } _flags;
    NSInteger _mutationCheckInteger;
}

- (instancetype)init
{
    return [self initWithEntries:nil delegate:nil];
}

- (instancetype)initWithEntries:(nullable NSArray *)arrayOfLRUEntries delegate:(nullable id<TNLLRUCacheDelegate>)delegate
{
    if (self = [super init]) {
        _cache = [[NSMutableDictionary alloc] init];
        [self internalSetDelegate:delegate];
        for (id<TNLLRUEntry> entry in arrayOfLRUEntries) {
            [self appendEntry:entry];
        }
    }
    return self;
}

- (void)internalSetDelegate:(nullable id<TNLLRUCacheDelegate>)delegate
{
    _flags.delegateSupportsDidEvictSelector = (NO != [delegate respondsToSelector:@selector(tnl_cache:didEvictEntry:)]);
    _flags.delegateSupportsCanEvictSelector = (NO != [delegate respondsToSelector:@selector(tnl_cache:canEvictEntry:)]);
    _delegate = delegate;
}

- (void)setDelegate:(nullable id<TNLLRUCacheDelegate>)delegate
{
    [self internalSetDelegate:delegate];
}

#pragma mark Setting

- (void)addEntry:(id<TNLLRUEntry>)entry
{
    TNLAssert(entry != nil);
    if (entry == nil) {
        return;
    }

    if (entry == _headEntry) {
        return;
    }

    NSString *identifier = entry.LRUEntryIdentifier;
    TNLAssert(identifier != nil);
    if (gTwitterNetworkLayerAssertEnabled && _cache[identifier]) {
        TNLAssert((id)_cache[identifier] == (id)entry);
    }

    [self moveEntryToFront:entry];
    _cache[identifier] = entry;

    TNLLRUCacheAssertHeadAndTail(self);
}

- (void)appendEntry:(id<TNLLRUEntry>)entry
{
    TNLAssert(entry != nil);
    if (entry == nil) {
        return;
    }

    if (entry == _tailEntry) {
        return;
    }

    NSString *identifier = entry.LRUEntryIdentifier;
    TNLAssert(identifier != nil);
#ifndef __clang_analyzer__
    // clang analyzer reports identifier can be nil for the check   if (... && _cache[identifier]) {
    // just below.  (and then, if we ignore only that with #ifndef __clang_analyzer__, then it reports
    // _cache[identifier] within the TNLAssert() protected by the if stmt.)
    // however, in real life, the TNLAssert(identifier != nil) just above will prevent control from getting to
    // the if stmt at all when the global AssertEnabled variable is true, and when it is false, then the 2nd
    // part of the condition (and the stmts protected by the condition) will never be executed and won't crash.
    if (gTwitterNetworkLayerAssertEnabled && _cache[identifier]) {
        TNLAssert((id)_cache[identifier] == (id)entry);
    }
#endif

    _tailEntry.nextLRUEntry = entry;
    entry.previousLRUEntry = _tailEntry;
    entry.nextLRUEntry = nil;
    _tailEntry = entry;
    _cache[identifier] = entry;

    if (!_headEntry) {
        _headEntry = _tailEntry;
    }

    _mutationCheckInteger++;
    TNLLRUCacheAssertHeadAndTail(self);
}

#pragma mark Getting

- (NSUInteger)numberOfEntries
{
    return _cache.count;
}

- (nullable id<TNLLRUEntry>)entryWithIdentifier:(NSString *)identifier canMutate:(BOOL)canMutate
{
    id<TNLLRUEntry> entry = _cache[identifier];
    if (canMutate && entry) {
        [self moveEntryToFront:entry];
    }
    return entry;
}

- (nullable id<TNLLRUEntry>)entryWithIdentifier:(NSString *)identifier
{
    return [self entryWithIdentifier:identifier canMutate:YES];
}

- (NSArray *)allEntries
{
    NSMutableArray *entries = [[NSMutableArray alloc] initWithCapacity:self.numberOfEntries];

    id<TNLLRUEntry> current = self.headEntry;
    while (current != nil) {
        [entries addObject:current];
        current = current.nextLRUEntry;
    }

    return entries;
}

#pragma mark Removal

- (void)removeEntry:(nullable id<TNLLRUEntry>)entry
{
    if (!entry) {
        return;
    }

    NSString *identifier = entry.LRUEntryIdentifier;
    TNLAssert(identifier != nil);

    if (!identifier) {
        return;
    }

    TNLAssert(_cache[identifier] == entry);

    [self clearEntry:entry];
    [_cache removeObjectForKey:identifier];

    TNLLRUCacheAssertHeadAndTail(self);

    if (_flags.delegateSupportsDidEvictSelector) {
        [_delegate tnl_cache:self didEvictEntry:entry];
    }
}

- (nullable id<TNLLRUEntry>)removeTailEntry
{
    id<TNLLRUEntry> entry = _tailEntry;
    id<TNLLRUCacheDelegate> delegate = self.delegate;
    while (entry && _flags.delegateSupportsCanEvictSelector && ![delegate tnl_cache:self canEvictEntry:entry]) {
        entry = entry.previousLRUEntry;
    }
    [self removeEntry:entry];
    return entry;
}

#pragma mark Other

- (void)clearAllEntries
{
    // removing all entries via weak dealloc chaining
    // can yield a stack overflow!
    // use iterative removal instead

    id<TNLLRUEntry> entryToRemove = _headEntry;
    while (entryToRemove) {
        id<TNLLRUEntry> nextEntry = entryToRemove.nextLRUEntry;
        entryToRemove.nextLRUEntry = nil;
        entryToRemove.previousLRUEntry = nil;
        entryToRemove = nextEntry;
    }

    _tailEntry = nil;
    _headEntry = nil;
    [_cache removeAllObjects];
    _mutationCheckInteger++;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained __nullable [__nonnull])buffer count:(NSUInteger)len
{
    // Prep the number of enumerations made in this pass
    NSUInteger count = 0;

    // Initialization
    if (!state->state && !state->extra[0]) {
        // Track mutations using the current "start" location
        state->mutationsPtr = (void *)&_mutationCheckInteger;

        // Set the state as the current item to iterate on
        state->state = (unsigned long)_headEntry;

        // Flag that we started
        state->extra[0] = 1UL;
    }

    // Set the items pointer to the provided convenience buffer
    state->itemsPtr = buffer;

    // Now we provide items
    for ( ; state->state != 0UL && count < len; count++) {

        // Get the current entry
        __unsafe_unretained id<TNLLRUEntry> entry = (__bridge id<TNLLRUEntry>)(void *)state->state;

        // Add the current entry to the buffer
        buffer[count] = entry;

        // Get the next entry
        entry = entry.nextLRUEntry;

        // Update the state to the next entry
        state->state = (unsigned long)entry;
    }

    return count; // count of 0 ends the enumeration
}

#pragma mark Private

- (void)clearEntry:(id<TNLLRUEntry>)entry
{
    id<TNLLRUEntry> prev = entry.previousLRUEntry;
    id<TNLLRUEntry> next = entry.nextLRUEntry;
    prev.nextLRUEntry = next;
    next.previousLRUEntry = prev;
    entry.previousLRUEntry = nil;
    entry.nextLRUEntry = nil;
    if (entry == _tailEntry) {
        _tailEntry = prev;
    }
    if (entry == _headEntry) {
        _headEntry = next;
    }
    _mutationCheckInteger++;
}

- (void)moveEntryToFront:(id<TNLLRUEntry>)entry
{
    if (_headEntry == entry) {
        return;
    }

    id<TNLLRUEntry> previous = entry.previousLRUEntry;
    if (previous) {
        // in the linked list
        BOOL update = entry.shouldAccessMoveLRUEntryToHead;
        if (!update) {
            // don't update in LRU
            return;
        }
    }

    if (entry == _tailEntry) {
        _tailEntry = previous;
    }

    previous.nextLRUEntry = entry.nextLRUEntry;
    entry.nextLRUEntry.previousLRUEntry = previous;
    entry.previousLRUEntry = nil;
    entry.nextLRUEntry = _headEntry;
    _headEntry.previousLRUEntry = entry;
    _headEntry = entry;

    if (!_tailEntry) {
        _tailEntry = entry;
        TNLAssert(entry.nextLRUEntry == nil);
        TNLAssert(previous == nil);
    }

    _mutationCheckInteger++;
    TNLAssert(!_headEntry == !_tailEntry);
}

@end

NS_ASSUME_NONNULL_END


//
//  NSCoder+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created by Nolan on 6/5/19.
//  Copyright © 2019 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Additional methods for `NSCoder`
 */
@interface NSCoder (TNLAdditions)

/**
 Convenience method for loading an array with a known item class it will contain.
 It can handle the decoded object being an array of the known class or just being an instance of the class itself.

 @param itemClass the class of items in the encoded array
 @param key the key that the object was encoded with
 @return an `NSArray` of objects of the given _itemClass_ if decoding succeeds.
 */
- (nullable NSArray *)tnl_decodeArrayOfItemsOfClass:(Class)itemClass forKey:(NSString *)key;
/**
 Convenience method for loading an array with a known set of classes its items will contain.
 It can handle the decoded object being an array of the known classes or just being an instance of one of the classes.

 @param itemClasses the classes of items in the encoded array
 @param key the key that the object was encoded with
 @return an `NSArray` of objects of the given _itemClasses_ if decoding succeeds.
 */
- (nullable NSArray *)tnl_decodeArrayOfItemsOfClasses:(NSSet<Class> *)itemClasses forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

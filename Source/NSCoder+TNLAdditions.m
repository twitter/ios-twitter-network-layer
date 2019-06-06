//
//  NSCoder+TNLAdditions.m
//  TwitterNetworkLayer
//
//  Created by Nolan on 6/5/19.
//  Copyright © 2019 Twitter. All rights reserved.
//

#import "NSCoder+TNLAdditions.h"
#import "TNL_Project.h"

@implementation NSCoder (TNLAdditions)

- (nullable NSArray *)tnl_decodeArrayOfItemsOfClass:(Class)itemClass forKey:(NSString *)key
{
    return [self tnl_decodeArrayOfItemsOfClasses:[NSSet setWithObject:itemClass] forKey:key];
}

- (nullable NSArray *)tnl_decodeArrayOfItemsOfClasses:(NSSet<Class> *)itemClasses forKey:(NSString *)key
{
    /**
     OK, decoding containers is wonky as heck with NSCoder w/ secure coding.
     You MUST specify both the concrete object classes that will be in the container AND
     the container(s) itself/themselves.

     We just care about an array here, so we add the `[NSArray class]` to the classes to decode.
     If we had an NSDictionary of NSArray instances of NSDate objects, we would need to provide
     `[NSDictionary class]`, `[NSArray class]` and `[NSDate class]` as the classes 😬

     Now, since we are decoding with support for `NSArray` and the given item classes, we could get
     back either an `NSArray` of item classes OR just a single instance of any one of the item classes.
     To avoid unexpected return values, we will coerce anything that is a single instance into an
     array of 1 object - preserving our expectation for an array return value.

     If we were to try to decode just as an `NSArray` class, the decode would fail.
     If we were to try to decode with just the item class(es), the decode would fail.
     So, we'll use this convenience method to make it easier to decode our expected arrays within TNL.

     The documentation for how this works is pretty non-existant:
     https://developer.apple.com/documentation/foundation/nscoder/1442560-decodeobjectofclasses?language=objc
     and in `NSCoder.h` there is just the signature, no comment.
     */

    id valueRaw = [self decodeObjectOfClasses:[itemClasses setByAddingObject:[NSArray class]] forKey:key];
    if (valueRaw != nil) {
        if ([itemClasses containsObject:[valueRaw class]]) {
            return @[valueRaw];
        }
        if ([valueRaw isKindOfClass:[NSArray class]]) {
            return valueRaw;
        }

        // got the wrong value -- should NEVER happen since the decode should
        // catch anything outside of expectations.
        TNLAssertNever();
        [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSCoderReadCorruptError
                                            userInfo:@{
                                                       NSDebugDescriptionErrorKey:
                                                       [NSString stringWithFormat:@"value for key '%@' was of unexpected class '%@'.  Allowed classes are '%@'.", key, NSStringFromClass([valueRaw class]), itemClasses.allObjects]
                                                       }]];
    }
    return nil;
}

@end

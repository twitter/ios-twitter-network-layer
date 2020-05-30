//
//  NSNumber+TNLURLCoding.h
//  TwitterNetworkLayer
//
//  Created on 9/17/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TwitterNetworkLayer/TNLURLCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLBoolean;

/**
 `NSNumber(TNLURLCoding)` is a category on `NSNumber` to add helpers for encoding  support.
 TNL treats `NSNumber` as a first class object for encoding. The encoding of an `NSNumber` is based
 on the `TNLURLEncodableDictionaryOptionReplaceDictionariesWithDictionariesOfEncodableStrings`
 option being present or not.

 ## Custom encoding of numbers

 If a consumer wishes to encode a number in a different way the consumer can use a different object
 instead of an `NSNumber`.
 For convenience, `TNLBoolean` is provided so that the object can be encoded as `@"true"` or
 `@"false"` based on the `boolValue` of the object always, regardless of encoding format or options.
 */
@interface NSNumber (TNLBooleanCoding)

/**
 Returns a `TNLBoolean` object that will encode as `@"true"` or `@"false"` based on the receiver's
 `boolValue`.
 */
- (TNLBoolean *)tnl_booleanObject;

/**
 Is the underlying number a boolean?
 */
- (BOOL)tnl_isBoolean;

@end

/**
 Category for converting numbers to strings
 */
@interface NSNumber (TNLStringCoding)

/**
 For most `NSNumber` instances, this is a faster way of getting the string value than `stringValue`
 or `descriptionWithLocale:`.
 Interally falls back to `descriptionWithLocale:` if it cannot convert (never encountered a case yet).

 Random sampling on 124,000 NSNumbers on 1 thread (via Xcode Simulator on 10-core 3GHz Xeon W)
 -[NSNumber stringValue] = 1.149726s
 -[NSNumber tnl_quickStringValue] = 0.775426s
 Pretty consistently achieves 33% speedup on average.
 Using `TNLURLEncodeDictionary` for converting a `TNLRequestConfiguration` into an identifier string
 (very regular within TNL) has more than 60% speedup.
 */
- (NSString *)tnl_quickStringValue;

@end

/**
 `TNLBoolean` is a convenience object in case it is desirable to have an object for URL encoding
 that is boolean and will yield either `@"true"` or `@"false"` always instead of conditionally based
 on the way an `NSNumber` is structured.
 */
@interface TNLBoolean : NSObject <TNLURLEncodableObject>

/** The value as a `BOOL` */
@property (nonatomic, readonly) BOOL boolValue;

/** The value as an `NSString` */
- (NSString *)stringValue;
/** The value as an `NSNumber` */
- (NSNumber *)numberValue;

/** Designated initializer */
- (instancetype)initWithBool:(BOOL)boolValue NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END

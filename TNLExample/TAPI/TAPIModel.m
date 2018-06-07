//
//  TAPIModel.m
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import "TAPIModel.h"

@interface TAPIUserObject : NSObject <TAPIUserModel>
@property (nonatomic, readonly) long long userID;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *screenName;
- (instancetype)initWithJSONObject:(id)object;
@end

@interface TAPIImageEntityVariantObject : NSObject <TAPIImageEntityVariantModel>
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) CGSize dimensions;
- (instancetype)initWithName:(NSString *)name dimensions:(CGSize)dims;
@end

@interface TAPIImageEntityObject : NSObject <TAPIImageEntityModel>
@property (nonatomic, readonly, copy) NSString *baseURLString;
@property (nonatomic, readonly, copy) NSString *format;
@property (nonatomic, readonly, copy) NSArray<id<TAPIImageEntityVariantModel>> *variants;
- (instancetype)initWithJSONObject:(id)object;
@end

@interface TAPIStatusObject : NSObject<TAPIStatusModel>
@property (nonatomic, readonly) long long statusID;
@property (nonatomic, readonly) NSDate *creationDate;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) long long retweetCount;
@property (nonatomic, readonly) long long favoriteCount;
@property (nonatomic, readonly) BOOL possiblySensitive;
@property (nonatomic, readonly) id<TAPIUserModel> user;
@property (nonatomic, readonly, copy) NSArray<id<TAPIImageEntityModel>> *images;
- (instancetype)initWithJSONObject:(id)object;
@end

@implementation TAPIUserObject

- (instancetype)initWithJSONObject:(id)object
{
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    _userID = [object[@"id"] longLongValue];
    _name = [object[@"name"] copy];
    _screenName = [object[@"screen_name"] copy];
    if (_screenName.length == 0 || !_name || !_userID) {
        return nil;
    }

    return self;
}

@end

@implementation TAPIImageEntityVariantObject

- (instancetype)initWithName:(NSString *)name dimensions:(CGSize)dims
{
    if (!name.length) {
        return nil;
    }

    if (dims.height <= 0 || dims.width <= 0) {
        return nil;
    }

    _name = [name copy];
    _dimensions = dims;
    return self;
}

@end

@implementation TAPIImageEntityObject

- (instancetype)initWithJSONObject:(id)object
{
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *media = object;
    if (![media[@"type"] isEqual:@"photo"]) {
        return nil;
    }

    NSString *URLString = media[@"media_url_https"];
    if (URLString.length == 0) {
        return nil;
    }

    _format = [URLString pathExtension];
    if (_format.length == 0) {
        return nil;
    }

    _baseURLString = [URLString substringToIndex:URLString.length - (_format.length + 1)];
    if (_baseURLString.length == 0) {
        return nil;
    }

    NSDictionary *sizes = media[@"sizes"];
    if (![sizes isKindOfClass:[NSDictionary class]] || sizes.count == 0) {
        return nil;
    }

    NSMutableArray<id<TAPIImageEntityVariantModel>> *variants = [[NSMutableArray alloc] initWithCapacity:sizes.count];
    for (NSString *variantName in sizes.allKeys) {
        NSDictionary *info = sizes[variantName];
        if (![info isKindOfClass:[NSDictionary class]] || ![info[@"resize"] isEqual:@"fit"]) {
            continue;
        }
        const CGSize dims = CGSizeMake((CGFloat)[info[@"w"] integerValue], (CGFloat)[info[@"h"] integerValue]);
        id<TAPIImageEntityVariantModel> variant = [[TAPIImageEntityVariantObject alloc] initWithName:variantName dimensions:dims];
        if (variant) {
            [variants addObject:variant];
        }
    }
    if (!variants.count) {
        return nil;
    }
    [variants sortUsingComparator:^NSComparisonResult(id<TAPIImageEntityVariantModel> obj1, id<TAPIImageEntityVariantModel> obj2) {
        const NSUInteger pixels1 = (NSUInteger)obj1.dimensions.width * (NSUInteger)obj1.dimensions.width;
        const NSUInteger pixels2 = (NSUInteger)obj2.dimensions.width * (NSUInteger)obj2.dimensions.width;
        if (pixels1 == pixels2) {
            return NSOrderedSame;
        }
        if (pixels1 < pixels2) {
            return NSOrderedAscending;
        }
        return NSOrderedDescending;
    }];
    id<TAPIImageEntityVariantModel> lastVariant = variants.firstObject;
    for (NSUInteger i = 1; i < variants.count; i++) {
        id<TAPIImageEntityVariantModel> variant = variants[i];
        if (CGSizeEqualToSize(variant.dimensions, lastVariant.dimensions)) {
            // trim up the variants
            while (i < variants.count) {
                [variants removeLastObject];
            }
            break;
        }
        lastVariant = variant;
    }
    _variants = [variants copy];

    return self;
}

@end

@implementation TAPIStatusObject

- (instancetype)initWithJSONObject:(id)object
{
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    _statusID = [object[@"id"] longLongValue];
    _creationDate = TNLHTTPDateFromString(object[@"created_at"], NULL);
    _text = [object[@"text"] copy];
    _retweetCount = [object[@"retweet_count"] longLongValue];
    _favoriteCount = [object[@"favorite_count"] longLongValue];
    _possiblySensitive = [object[@"possibly_sensitive"] boolValue];
    _user = [[TAPIUserObject alloc] initWithJSONObject:object[@"user"]];

    NSDictionary *entities = object[@"entities"];
    if ([entities isKindOfClass:[NSDictionary class]]) {
        NSArray *media = entities[@"media"];
        if ([media isKindOfClass:[NSArray class]]) {
            NSMutableArray<id<TAPIImageEntityModel>> *images = [[NSMutableArray alloc] initWithCapacity:4];
            for (id mediaValue in media) {
                id<TAPIImageEntityModel> image = [[TAPIImageEntityObject alloc] initWithJSONObject:mediaValue];
                if (image) {
                    [images addObject:image];
                }
            }
            _images = (images.count > 0) ? [images copy] : nil;
        }
    }

    if (!_statusID || !_creationDate || !_user) {
        return nil;
    }

    return self;
}

@end

NSArray<id<TAPIStatusModel>> *TAPIStatusModelsFromJSONObjects(NSArray<id> *objects)
{
    NSMutableArray *models = [[NSMutableArray alloc] initWithCapacity:objects.count];
    for (id object in objects) {
        @autoreleasepool {
            id<TAPIStatusModel> status = [[TAPIStatusObject alloc] initWithJSONObject:object];
            if (status) {
                [models addObject:status];
            }
        }
    }
    return (models.count > 0) ? models : nil;
}

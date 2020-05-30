//
//  TAPIModel.h
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <CoreGraphics/CGGeometry.h>
#import <Foundation/Foundation.h>

@protocol TAPIUserModel <NSObject>
@property (nonatomic, readonly) long long userID;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *screenName;
@end

@protocol TAPIImageEntityVariantModel <NSObject>
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) CGSize dimensions;
@end

@protocol TAPIImageEntityModel <NSObject>
@property (nonatomic, readonly, copy) NSString *baseURLString;
@property (nonatomic, readonly, copy) NSString *format;
@property (nonatomic, readonly, copy) NSArray<id<TAPIImageEntityVariantModel>> *variants;
@end

@protocol TAPIStatusModel <NSObject>
@property (nonatomic, readonly) long long statusID;
@property (nonatomic, readonly) NSDate *creationDate;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) long long retweetCount;
@property (nonatomic, readonly) long long favoriteCount;
@property (nonatomic, readonly) BOOL possiblySensitive;
@property (nonatomic, readonly) id<TAPIUserModel> user;
@property (nonatomic, readonly, copy) NSArray<id<TAPIImageEntityModel>> *images;
@end

FOUNDATION_EXTERN NSArray<id<TAPIStatusModel>> *TAPIStatusModelsFromJSONObjects(NSArray<id> *objects);

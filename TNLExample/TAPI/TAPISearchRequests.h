//
//  TAPISearchRequests.h
//  TNLExample
//
//  Created on 5/24/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TAPIModel.h"
#import "TAPIRequest.h"
#import "TAPIResponse.h"

@interface TAPISearchRequest : TAPIRetriableRequest
- (instancetype)initWithQuery:(NSString *)query;
- (instancetype)initWithNextResultsObject:(id)nextResultsObject;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface TAPISearchResponse : TAPIResponse
@property (nonatomic, readonly, copy) NSArray<id<TAPIStatusModel>> *statuses;
@property (nonatomic, readonly, copy) id nextResultsObject;

- (NSArray<id<TAPIImageEntityModel>> *)imagesFromStatuesRemovingSensitiveImages:(BOOL)removeSensitive;
@end

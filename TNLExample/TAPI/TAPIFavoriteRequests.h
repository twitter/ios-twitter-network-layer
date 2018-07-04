//
//  TAPIFavoriteRequests.h
//  TNLExample
//
//  Created on 5/24/18.
//  Copyright © 2018 Twitter. All rights reserved.
//

#import "TAPIRequest.h"
#import "TAPIResponse.h"

@interface TAPIFavoriteBaseRequest : TAPIRetriableRequest <TAPIUndoableRequest>
- (instancetype)initWithStatusID:(long long)statusID undo:(BOOL)undo;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface TAPIFavoriteCreateRequest : TAPIFavoriteBaseRequest
- (instancetype)initWithStatusID:(long long)statusID;
- (instancetype)initWithStatusID:(long long)statusID undo:(BOOL)undo NS_UNAVAILABLE;
@end

@interface TAPIFavoriteDestroyRequest : TAPIFavoriteBaseRequest
- (instancetype)initWithStatusID:(long long)statusID;
- (instancetype)initWithStatusID:(long long)statusID undo:(BOOL)undo NS_UNAVAILABLE;
@end

@interface TAPIFavoriteResponse : TAPIResponse <TAPIActionResponse>
@end

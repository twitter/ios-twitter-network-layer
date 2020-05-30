//
//  TAPIFavoriteRequests.m
//  TNLExample
//
//  Created on 5/24/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TAPIFavoriteRequests.h"

@implementation TAPIFavoriteBaseRequest
{
    long long _statusID;
}

@synthesize undo = _undo;

- (instancetype)initWithStatusID:(long long)statusID undo:(BOOL)undo
{
    if (self = [super init]) {
        _undo = undo;
        _statusID = statusID;
    }
    return self;
}

- (NSString *)endpoint
{
    return _undo ? @"favorites/destroy.json" : @"favorites/create.json";
}

- (void)prepareParameters:(TNLMutableParameterCollection *)params
{
    [super prepareParameters:params];
    params[@"id"] = @(_statusID);
}

- (TNLHTTPMethod)HTTPMethodValue
{
    return TNLHTTPMethodPOST;
}

+ (Class)responseClass
{
    return [TAPIFavoriteResponse class];
}

@end

@implementation TAPIFavoriteCreateRequest

- (instancetype)initWithStatusID:(long long)statusID
{
    return [super initWithStatusID:statusID undo:NO];
}

@end

@implementation TAPIFavoriteDestroyRequest

- (instancetype)initWithStatusID:(long long)statusID
{
    return [super initWithStatusID:statusID undo:YES];
}

@end

@implementation TAPIFavoriteResponse

@synthesize didSucceed = _didSucceed;

- (void)prepare
{
    [super prepare];
    _didSucceed = (200 == _info.statusCode);
}

@end

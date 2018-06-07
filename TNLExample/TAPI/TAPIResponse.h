//
//  TAPIResponse.h
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

@protocol TAPIActionResponse
@property (nonatomic, readonly) BOOL didSucceed;
@end

@interface TAPIResponse : TNLResponse
{
@protected
    NSError *_apiError;
    NSError *_parseError;
    id _parsedObject;
}

@property (nonatomic, readonly) NSError *apiError;
@property (nonatomic, readonly) NSError *parseError;
@property (nonatomic, readonly) id parsedObject;

- (NSError *)anyError; // operationError or parseError or apiError

@end

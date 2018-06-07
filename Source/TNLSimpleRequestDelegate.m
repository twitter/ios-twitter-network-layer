//
//  TNLSimpleRequestDelegate.m
//  TwitterNetworkLayer
//
//  Created on 11/25/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLSimpleRequestDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TNLSimpleRequestDelegate

- (instancetype)initWithDidCompleteBlock:(TNLRequestDidCompleteBlock)didCompleteBlock
{
    if (self = [super init]) {
        TNLAssert(didCompleteBlock != NULL);
        _didCompleteBlock = [didCompleteBlock copy];
    }
    return self;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteWithResponse:(TNLResponse *)response
{
    self.didCompleteBlock(op, response);
}

@end

NS_ASSUME_NONNULL_END

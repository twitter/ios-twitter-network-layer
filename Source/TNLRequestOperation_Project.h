//
//  TNLRequestOperation_Project.h
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLRequestOperation.h"
#import "TNLResponse.h"
#import "TNLURLSessionTaskOperation.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

@class TNLRequestOperationQueue, TNLURLSessionTaskOperation;
@protocol TNLContentDecoder;

#if __LP64__ || (TARGET_OS_EMBEDDED && !TARGET_OS_IPHONE) || TARGET_OS_WIN32 || NS_BUILD_32_LIKE_64
#define TNLRequestOperationState_Unaligned_AtomicT volatile atomic_int_fast64_t
#define TNLRequestOperationState_AtomicT TNLRequestOperationState_Unaligned_AtomicT __attribute__((aligned(8)))
#else
#define TNLRequestOperationState_Unaligned_AtomicT volatile atomic_int_fast32_t
#define TNLRequestOperationState_AtomicT TNLRequestOperationState_Unaligned_AtomicT __attribute__((aligned(4)))
#endif

@interface TNLRequestOperation (Project) <TNLURLSessionTaskOperationDelegate>

// Init
- (instancetype)initWithRequest:(nullable id<TNLRequest>)request
                  responseClass:(nullable Class)responseClass
                  configuration:(nullable TNLRequestConfiguration *)config
                       delegate:(nullable id<TNLRequestDelegate>)delegate; // NS_DESIGNATED_INITIALIZER

// Prep
- (void)enqueueToOperationQueue:(TNLRequestOperationQueue *)operationQueue;

// Properties
@property (atomic, nullable, readonly) TNLURLSessionTaskOperation *URLSessionTaskOperation;
@property (atomic, copy, nullable, readonly) NSDictionary<NSString *, id<TNLContentDecoder>> *additionalDecoders;
@property (atomic, copy, nullable, readonly) NSURLRequest *hydratedURLRequest;

@end

NS_ASSUME_NONNULL_END

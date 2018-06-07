//
//  TNLRequestOperationQueue_Project.h
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import "TNLAttemptMetrics.h"
#import "TNLHTTPHeaderProvider.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLRequestEventHandler.h"
#import "TNLRequestOperationQueue.h"
#import "TNLURLSessionManager.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

@class TNLURLSessionTaskOperation;
@class TNLTemporaryFile;

@interface TNLRequestOperationQueue (Project)

+ (NSOperationQueue *)globalRequestOperationQueue;

#pragma mark Request Operation

- (void)syncAddRequestOperation:(TNLRequestOperation *)op;
- (void)clearQueuedRequestOperation:(TNLRequestOperation *)op;

#pragma mark URL Session Task Operation

- (void)findURLSessionTaskOperationForRequestOperation:(TNLRequestOperation *)op
                                              complete:(TNLRequestOperationQueueFindTaskOperationCompleteBlock)complete; // always yields a task operation

#pragma mark Network Observer

+ (void)addGlobalNetworkObserver:(id<TNLNetworkObserver>)observer;
+ (void)removeGlobalNetworkObserver:(id<TNLNetworkObserver>)observer;
+ (NSArray<id<TNLNetworkObserver>> *)allGlobalNetworkObservers;

+ (void)addGlobalHeaderProvider:(id<TNLHTTPHeaderProvider>)provider;
+ (void)removeGlobalHeaderProvider:(id<TNLHTTPHeaderProvider>)provider;
+ (nullable NSArray<id<TNLHTTPHeaderProvider>> *)allGlobalHeaderProviders;

- (void)operationDidStart:(TNLRequestOperation *)op;
- (void)operation:(TNLRequestOperation *)op
        didStartAttemptWithMetrics:(TNLAttemptMetrics *)metrics;
- (void)operation:(TNLRequestOperation *)op
        didCompleteAttempt:(TNLResponse *)response
        disposition:(TNLAttemptCompleteDisposition)disposition;
- (void)operation:(TNLRequestOperation *)op
        didCompleteWithResponse:(TNLResponse *)response;

// for anonymous task operation completion
- (void)taskOperation:(TNLURLSessionTaskOperation *)op
   didCompleteAttempt:(TNLResponse *)response;

@end

NS_ASSUME_NONNULL_END

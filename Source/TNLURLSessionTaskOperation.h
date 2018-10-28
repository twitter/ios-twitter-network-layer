//
//  TNLURLSessionTaskOperation.h
//  TwitterNetworkLayer
//
//  Created on 6/11/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLAttemptMetaData.h"
#import "TNLRequestAuthorizer.h"
#import "TNLRequestConfiguration.h"
#import "TNLRequestOperationState.h"
#import "TNLRequestRedirecter.h"
#import "TNLResponse.h"
#import "TNLSafeOperation.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

@class TNLTemporaryFile;
@class TNLRequestOperation;
@class TNLRequestOperationQueue;
@class NSURLSessionTaskMetrics;
@protocol TNLURLSessionManager;
@protocol TNLURLSessionTaskOperationDelegate;
@protocol TNLAuthenticationChallengeHandler;

@interface TNLURLSessionTaskOperation : TNLSafeOperation <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>

- (nullable NSURLSession *)URLSession;
@property (nonatomic, readonly, nullable) TNLRequestOperationQueue *requestOperationQueue;
@property (nonatomic, readonly, nullable) NSURLSessionTask *URLSessionTask; // set during Connecting state
@property (nonatomic, readonly) TNLRequestExecutionMode executionMode; // set during init
@property (nonatomic, readonly) TNLPriority requestPriority; // set during init but can be updated dynamically
@property (nonatomic, readonly) TNLRequestConfiguration *requestConfiguration;
@property (nonatomic, readonly, nullable) TNLResponseInfo *responseInfo;
@property (nonatomic, readonly) TNLResponseSource responseSource;
@property (nonatomic, readonly, nullable) TNLResponse *finalResponse;
@property (nonatomic, readonly) NSURLRequest *hydratedURLRequest;
@property (nonatomic, weak, readonly, nullable) TNLRequestOperation<TNLURLSessionTaskOperationDelegate> *requestOperation;

@property (nonatomic, readonly, nullable) NSURLRequest *originalURLRequest;
@property (nonatomic, readonly, nullable) NSURL *originalURL;
@property (nonatomic, readonly, nullable) NSURLRequest *currentURLRequest;
@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly, nullable) NSHTTPURLResponse *URLResponse;

@property (nonatomic, readonly, nullable) NSError *error;

@end

@interface TNLURLSessionTaskOperation (TNLRequestOperationQueueMethods)

- (void)setURLSession:(NSURLSession *)URLSession supportsTaskMetrics:(BOOL)taskMetrics; // set by TNLRequestOperationQueue ONLY

- (void)enqueueToOperationQueueIfNeeded:(TNLRequestOperationQueue *)operationQueue;
- (void)dissassociateRequestOperation:(TNLRequestOperation *)op;
- (void)cancelWithSource:(nullable id)optionalSource
         underlyingError:(nullable NSError *)optionalUnderlyingError;
- (TNLRequestOperation *)synthesizeRequestOperation;

- (instancetype)initWithRequestOperation:(TNLRequestOperation *)op
                          sessionManager:(id<TNLURLSessionManager>)sessionManager;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface TNLURLSessionTaskOperation (TNLURLSessionManagerMethods)
- (void)handler:(id<TNLAuthenticationChallengeHandler>)handler
        didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
        forURLSession:(NSURLSession *)session;
@end

@interface TNLURLSessionTaskOperation (TNLRequestOperationMethods)

// call these from tnl_network_queue()
- (void)network_priorityDidChangeForRequestOperation:(TNLRequestOperation *)op;
- (TNLAttemptMetaData *)network_metaData;
- (nullable NSURLSessionTaskMetrics *)network_taskMetrics;

@end

@class NSURLSessionTaskMetrics;

typedef void(^TNLRequestMakeFinalResponseCompletionBlock)(TNLResponse * __nullable response);

// All calls are made from tnl_network_queue()
// All completion blocks MUST be made from tnl_network_queue()
@protocol TNLURLSessionTaskOperationDelegate <NSObject>
@required
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                   didTransitionToState:(TNLRequestOperationState)state
                           withResponse:(nullable TNLResponse *)response;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
         didStartSessionTaskWithRequest:(NSURLRequest *)request;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
               finalizeWithResponseInfo:(TNLResponseInfo *)responseInfo
                          responseError:(nullable NSError *)responseError
                               metaData:(TNLAttemptMetaData *)metadata
                            taskMetrics:(nullable NSURLSessionTaskMetrics *)taskMetrics
                             completion:(TNLRequestMakeFinalResponseCompletionBlock)completion;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                didUpdateUploadProgress:(float)progress;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
              didUpdateDownloadProgress:(float)progress;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                     appendReceivedData:(NSData *)data;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
        didStartTaskWithTaskIdentifier:(NSUInteger)taskId
        configIdentifier:(nullable NSString *)configIdentifier
        sharedContainerIdentifier:(nullable NSString *)sharedContainerIdentifier
        isBackgroundRequest:(BOOL)isBackgroundRequest;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
         willPerformRedirectFromRequest:(NSURLRequest *)fromRequest
                       withHTTPResponse:(NSHTTPURLResponse *)response
                              toRequest:(NSURLRequest *)toRequest
                             completion:(TNLRequestRedirectCompletionBlock)completion;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                         redirectedFrom:(NSURLRequest *)fromRequest
                       withHTTPResponse:(NSHTTPURLResponse *)response
                                     to:(NSURLRequest *)toRequest
                               metaData:(TNLAttemptMetaData *)metaData;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                    redirectFromRequest:(NSURLRequest *)fromRequest
                       withHTTPResponse:(NSHTTPURLResponse *)response
                                     to:(NSURLRequest *)toRequest
                      completionHandler:(void (^)(NSURLRequest * __nullable, NSError * __nullable error))completionHandler;
- (void)network_URLSessionTaskOperation:(TNLURLSessionTaskOperation *)taskOp
                  didReceiveURLResponse:(NSURLResponse *)URLResponse;
- (void)network_URLSessionTaskOperationIsWaitingForConnectivity:(TNLURLSessionTaskOperation *)taskOp;
@end

NS_ASSUME_NONNULL_END

//
//  TNLXDummy.m
//  TwitterNetworkLayer
//
//  Created on 8/29/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import "TNLXDummy.h"

// TODO:[nobrien] - improve this dummy code
/*
 For each network type (NSURL and TNL)
 Create a VC to do 1 simple request
 Create a VC to do a chain of requests (bing search followed by auto rendering the image and displaying it)

 Just for TNL create a stub VC playground
 */

#define NSURL_MODE 0

@interface DummyVC ()

@property (nonatomic) id action;
@property (nonatomic) NSURLSession *session;
@property (nonatomic) NSURLSessionTask *task;
@property (nonatomic) NSArray *ops;
@property (nonatomic) NSArray *tasks;
@property (nonatomic) BOOL loaded;
@property (nonatomic) NSOperation *someOperationToDependOn;

- (void)startNetworkOperationIfNeeded;
- (void)handleCompletedAction:(id)action URLResponse:(NSURLResponse *)r data:(NSData *)data error:(NSError *)error originalRequest:(id<TNLRequest>)originalReq hydratedRequest:(id<TNLRequest>)hydratedReq finalRequest:(id<TNLRequest>)finalReq uploadProgress:(float)uploadProgress downloadProgress:(float)downloadProgress retryCount:(NSUInteger)retryCount wasCancelled:(BOOL)wasCancelled;

@end

@implementation DummyVC

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self startNetworkOperationIfNeeded];
}

- (void)dealloc
{
    [self.action cancel];
}

- (void)startNetworkOperationIfNeeded
{
    if (self.loaded || self.action) {
        return;
    }

    NSURL *someURL = [NSURL URLWithString:@"http://twitter.com/some/url"];
    __weak typeof(self) weakSelf = self;

#if NSURL_MODE

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.session = [NSURLSession sessionWithConfiguration:config];
    self.action = [self.session dataTaskWithURL:someURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf handleTask:strongSelf.task response:response data:data error:error];
        }
    }];
    [self.action resume];

#else

    self.action = [TNLRequestOperation operationWithURL:someURL completion:^(TNLRequestOperation *op, TNLResponse *response) {
        [weakSelf handleRequestOperation:op response:response];
    }];
    // Can interact with NSOperation interface
    [self.action addDependency:self.someOperationToDependOn];
    [self.action setCompletionBlock:^{
        NSLog(@"Sweet!  We can add a completion block that is separate from the callback/delegate system like any other NSOperation!");
    }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:self.action]; // or, if no NSOperation work needs to be configured, enqueueRequestWithURL:completion: could have been called

#endif
}

#if NSURL_MODE
- (void)handleTask:(NSURLSessionTask *)task response:(NSURLResponse *)r data:(NSData *)data error:(NSError *)error
{
    self.session = nil;
    BOOL wasCancelled = [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled;

    float uploadProgress = (task.countOfBytesExpectedToSend > 0) ? (double)task.countOfBytesSent / (double)task.countOfBytesExpectedToSend : 0; // not always available
    float downloadProgress = (task.countOfBytesExpectedToReceive > 0) ? (double)task.countOfBytesReceived / (double)task.countOfBytesExpectedToReceive : 0; // not always available

    [self handleCompletedAction:task
                    URLResponse:r
                           data:data
                          error:error
                originalRequest:task.originalRequest
                hydratedRequest:task.originalRequest /* always the original */
                   finalRequest:task.currentRequest
                 uploadProgress:uploadProgress
               downloadProgress:downloadProgress
                     retryCount:0 /* no such thing */
                   wasCancelled:wasCancelled];
}
#else
- (void)handleRequestOperation:(TNLRequestOperation *)op response:(TNLResponse *)r
{
    BOOL wasCancelled = [r.operationError.domain isEqualToString:TNLErrorDomain] && r.operationError.code == TNLErrorCodeRequestOperationCancelled;

    [self handleCompletedAction:op
                    URLResponse:r.info.URLResponse
                           data:r.info.data
                          error:r.operationError
                originalRequest:op.originalRequest
                hydratedRequest:op.hydratedRequest
                   finalRequest:r.info.finalURLRequest
                 uploadProgress:op.uploadProgress
               downloadProgress:op.downloadProgress
                     retryCount:(op.attemptCount > 0) ? op.attemptCount - 1 : 0
                   wasCancelled:wasCancelled];
}
#endif

- (void)handleCompletedAction:(id)action URLResponse:(NSURLResponse *)r data:(NSData *)data error:(NSError *)error originalRequest:(id<TNLRequest>)originalReq hydratedRequest:(id<TNLRequest>)hydratedReq finalRequest:(id<TNLRequest>)finalReq uploadProgress:(float)uploadProgress downloadProgress:(float)downloadProgress retryCount:(NSUInteger)retryCount wasCancelled:(BOOL)wasCancelled
{
    assert(action == self.action);
    self.action = nil;
    self.loaded = YES;
}

@end

//
//  TNLBackgroundURLSessionTaskOperationManager.m
//  TwitterNetworkLayer
//
//  Created on 8/6/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <mach/mach_time.h>
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLBackgroundURLSessionTaskOperationManager.h"
#import "TNLRequest.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLResponse.h"
#import "TNLTemporaryFile_Project.h"
#import "TNLTiming.h"
#import "TNLURLSessionManager.h"

NS_ASSUME_NONNULL_BEGIN

#define SELF_ARG PRIVATE_SELF(TNLBackgroundURLSessionTaskOperationManager)

@interface TNLBackgroundRequestContext : NSObject
@property (nonatomic, nullable) NSURLSessionTask *URLSessionTask;
@property (nonatomic, nullable) NSHTTPURLResponse *URLResponse;
@property (nonatomic, nullable) NSError *error;
@property (nonatomic, nullable) TNLTemporaryFile *tempFile;
@end

@interface TNLBackgroundURLSessionTaskOperationManager () <NSURLSessionDownloadDelegate, NSURLSessionDataDelegate>
static TNLBackgroundRequestContext * __nullable _getBackgroundRequestContext(SELF_ARG,
                                                                             NSURLSessionTask *task,
                                                                             BOOL createIfNecessary);
@end

@implementation TNLBackgroundURLSessionTaskOperationManager
{
    NSURLSession *_URLSession;
    NSMutableDictionary *_contexts;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _contexts = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)handleBackgroundURLSessionEvents:(NSString *)identifier
{
    // TODO: change this so that the URLSession is owned by TNLURLSessionManager
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration tnl_backgroundSessionConfigurationWithTaggedIdentifier:identifier];
    _URLSession = [NSURLSession sessionWithConfiguration:config
                                                delegate:self
                                           delegateQueue:[NSOperationQueue mainQueue]];
}

static TNLBackgroundRequestContext * __nullable _getBackgroundRequestContext(SELF_ARG,
                                                                             NSURLSessionTask *task,
                                                                             BOOL createIfNecessary)
{
    if (!self) {
        return nil;
    }

    NSNumber *taskIdNumber = @(task.taskIdentifier);
    TNLBackgroundRequestContext *context = self->_contexts[taskIdNumber];
    if (!context && createIfNecessary) {
        context = [[TNLBackgroundRequestContext alloc] init];
        context.URLSessionTask = task;
        self->_contexts[taskIdNumber] = context;
    }
    return context;
}

#pragma mark NSURLSessionDelegate

#if TARGET_OS_IPHONE // == IOS + WATCH + TV
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    TNLAssert(nil != session.configuration.identifier);
    [[TNLURLSessionManager sharedInstance] URLSessionDidCompleteBackgroundEvents:session];
}
#endif

- (void)URLSession:(NSURLSession *)session
        task:(NSURLSessionTask *)task
        didCompleteWithError:(nullable NSError *)error
{
    TNLBackgroundRequestContext *context = _getBackgroundRequestContext(self, task, YES /*createIfNecessary*/);
    TNLAssert(context != nil);
    TNLAssert(context.URLSessionTask.taskIdentifier == task.taskIdentifier);

    if (error && !context.error) {
        context.error = error;
    }

    if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {
        context.URLResponse = (id)task.response;
    }

    NSString *sharedContainerIdentifier = _URLSession.configuration.sharedContainerIdentifier;

    TNLResponseInfo *info = [[TNLResponseInfo alloc] initWithFinalURLRequest:task.currentRequest
                                                                 URLResponse:context.URLResponse
                                                                      source:TNLResponseSourceNetworkRequest
                                                                        data:nil
                                                          temporarySavedFile:context.tempFile];
    TNLResponseMetrics *metrics = [[TNLResponseMetrics alloc] initWithEnqueueDate:[NSDate date]
                                                                      enqueueTime:mach_absolute_time()
                                                                     completeDate:[NSDate date]
                                                                     completeTime:mach_absolute_time()
                                                                   attemptMetrics:nil];
    TNLResponse *response = [TNLResponse responseWithRequest:task.currentRequest
                                              operationError:context.error
                                                        info:info
                                                     metrics:metrics];
    [[TNLURLSessionManager sharedInstance] URLSessionDidCompleteBackgroundTask:task.taskIdentifier
                                                       sessionConfigIdentifier:_URLSession.configuration.identifier
                                                     sharedContainerIdentifier:sharedContainerIdentifier
                                                                       request:task.originalRequest
                                                                      response:response];
}

#pragma mark NSURLSessionDownloadTaskDelegate

- (void)URLSession:(NSURLSession *)session
        downloadTask:(NSURLSessionDownloadTask *)downloadTask
        didFinishDownloadingToURL:(NSURL *)location
{
    TNLBackgroundRequestContext *context = _getBackgroundRequestContext(self, downloadTask, YES /*createIfNecessary*/);
    TNLAssert(context != nil);
    TNLAssert(context.URLSessionTask.taskIdentifier == downloadTask.taskIdentifier);

    // Capture the temp file immediately
    NSError *error;
    context.tempFile = [TNLTemporaryFile temporaryFileWithExistingFilePath:location.path
                                                                     error:&error];
    if (!context.tempFile && !context.error) {
        context.error = error;
    }
}

@end

@implementation TNLBackgroundRequestContext
@end

NS_ASSUME_NONNULL_END

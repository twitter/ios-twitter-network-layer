//
//  TNLXSecondViewController.m
//  TNLExample
//
//  Created on 7/24/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import "TAPI.h"
#import "TNLXImageSupport.h"
#import "TNLXLotsOfRequestsViewController.h"

@import UIKit;

//#define REDUNDANCY (2) TODO
#define COUNT (50)
//#define SKIP (0) TODO
#define VARY_CONFIG 1
#define DOWNLOAD_IMAGES 0
#define NON_DOWNLOAD_IMAGES_CONSUMPTION_MODE TNLResponseDataConsumptionModeNone // TNLResponseDataConsumptionModeChunkToDelegateCallback
#define BACKGROUND_IMAGES 0
#define DELAY_BETWEEN_IMAGE_SCHEDULING (0.05)
#define MAX_REQUESTS (NSIntegerMax)
#define USE_CACHE 0

static const BOOL kUseThumbnail = NO;

@interface TNLXLotsOfRequestsViewController () <TNLRequestDelegate>
@end

@implementation TNLXLotsOfRequestsViewController
{
    UIProgressView *_progressView;
    IBOutlet UILabel *_totalLabel;
    IBOutlet UILabel *_activeLabel;
    IBOutlet UILabel *_completeLabel;
    IBOutlet UILabel *_okLabel;
    IBOutlet UILabel *_notOkLabel;
    IBOutlet UILabel *_errorLabel;
    IBOutlet UILabel *_bytesLabel;
    IBOutlet UILabel *_durationLabel;

    CFAbsoluteTime _startTime;
    TNLRequestOperation *_initialOp;
    NSArray<id<TAPIImageEntityModel>> *_results;
    NSMutableArray<TNLRequestOperation *> *_operations;
    uint64_t _bytesReceived;
    uint64_t _bytesTotal;
    NSUInteger _requestsComplete200;
    NSUInteger _requestsCompleteNot200;
    NSUInteger _requestsCompleteError;
    NSUInteger _requestsActive;
    NSUInteger _requestsSquashed;
    NSUInteger _cacheHits;
    TNLResponse *_longestResponse;

    TNLMutableRequestConfiguration *_imageConfig;
}

- (void)viewDidLoad
{
    [super viewDidLoad];


    if (!_imageConfig) {
        _imageConfig = [[TNLMutableRequestConfiguration alloc] init];

        _imageConfig.contributeToExecutingNetworkConnectionsCount = YES;
        _imageConfig.discretionary = YES;
        _imageConfig.networkServiceType = NSURLNetworkServiceTypeBackground;
        _imageConfig.URLCache = (USE_CACHE) ? [NSURLCache tnl_sharedURLCacheProxy] : nil;
        _imageConfig.protocolOptions = 0;
        _imageConfig.operationTimeout = 60;
        _imageConfig.attemptTimeout = 50;
        _imageConfig.idleTimeout = 20;
#if BACKGROUND_IMAGES
        _imageConfig.executionMode = TNLRequestExecutionModeBackground;
#else
        _imageConfig.executionMode = TNLRequestExecutionModeInApp;
#endif
#if DOWNLOAD_IMAGES
        _imageConfig.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
#else
        _imageConfig.responseDataConsumptionMode = NON_DOWNLOAD_IMAGES_CONSUMPTION_MODE;
#endif
    }

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    _progressView.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
    _progressView.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    _progressView.transform = CGAffineTransformMakeScale(1.0, self.view.bounds.size.height / _progressView.bounds.size.height);
    _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    _progressView.backgroundColor = [UIColor darkTextColor];
    [self.view insertSubview:_progressView atIndex:0];

    _totalLabel.text = nil;
    _activeLabel.text = nil;
    _completeLabel.text = nil;
    _okLabel.text = nil;
    _notOkLabel.text = nil;
    _errorLabel.text = nil;
    _bytesTotal = NSIntegerMax;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_backgroundDownloadDidComplete:)
                                                 name:TNLBackgroundRequestOperationDidCompleteNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_backgroundDownloadDidComplete:(NSNotification *)note
{
    NSLog(@"%@", note);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self _startInitialLoadIfNeeded];
}

- (void)_startInitialLoadIfNeeded
{
    if (!_initialOp && !_results) {
        _progressView.progress = 0;

        TAPISearchRequest *request = [[TAPISearchRequest alloc] initWithQuery:@"Xbox"];
        _initialOp = [[TAPIClient sharedInstance] startRequest:request delegate:self];
    }
}

- (void)_continueLoadWithNextResultsObject:(id)nextResultsObject
{
    assert(!_initialOp);
    TAPISearchRequest *request = [[TAPISearchRequest alloc] initWithNextResultsObject:nextResultsObject];
    _initialOp = [[TAPIClient sharedInstance] startRequest:request delegate:self];
}

- (void)_enqueueRequestWithImageEntity:(id<TAPIImageEntityModel>)image
{
    if (_operations.count >= MAX_REQUESTS) {
        return;
    }

    NSURL *imageURL = TNLXSelectBestImageURL(image, (kUseThumbnail) ? CGSizeMake(1, 1) : CGSizeZero, UIViewContentModeScaleAspectFill);
    NSURLRequest *urlReq = [NSURLRequest requestWithURL:imageURL];
#if VARY_CONFIG
    _imageConfig.attemptTimeout = _imageConfig.attemptTimeout+1;
#endif

    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:urlReq
                                                          configuration:_imageConfig
                                                               delegate:self];
    op.priority = TNLPriorityVeryLow;
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [_operations addObject:op];
    [self _update];
}

- (void)_dequeueRunningRequestWithResponse:(TNLResponse *)response
{
    if (response.operationError) {
        _requestsCompleteError++;
    } else if (response.info.statusCode == 200) {
        _requestsComplete200++;
    } else {
        _requestsCompleteNot200++;
    }

    const NSTimeInterval duration = response.metrics.totalDuration;
    const NSTimeInterval oldDuration = _longestResponse.metrics.totalDuration;

    if (oldDuration < duration) {
        _longestResponse = response;
        NSLog(@"New Longest Response: %@ %@", _longestResponse, _longestResponse.metrics);
    }

    if (response.info.source == TNLResponseSourceLocalCache) {
        _cacheHits++;
    }

    [self _updateComplete];
}

#pragma mark - Updates

- (void)_update
{
    _totalLabel.text = [NSString stringWithFormat:@"%tu", _operations.count];
    [self _updateComplete];
    [self _updateActive];
    [self _updateProgress];
}

- (void)_updateActive
{
    _activeLabel.text = [NSString stringWithFormat:@"%tu", _requestsActive];
    if (_requestsActive == 0) {
        [_progressView setProgress:1.0 animated:YES];
        CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - _startTime;
        _durationLabel.text = [NSString stringWithFormat:@"%.3f seconds", duration];
    } else {
        _durationLabel.text = nil;
    }
}

- (void)_updateComplete
{
    _completeLabel.text = [NSString stringWithFormat:@"(cache hit %tu) %tu", _cacheHits, (_requestsCompleteError + _requestsComplete200 + _requestsCompleteNot200)];
    _errorLabel.text = [NSString stringWithFormat:@"%tu", _requestsCompleteError];
    _okLabel.text = [NSString stringWithFormat:@"%tu", _requestsComplete200];
    _notOkLabel.text = [NSString stringWithFormat:@"%tu", _requestsCompleteNot200];
}

- (void)_updateProgress
{
    double progressSum = 0;
    const double progressTarget = MAX(_results.count, (NSUInteger)1);
    for (TNLRequestOperation *op in _operations) {
        progressSum += op.downloadProgress;
    }
    const float progress = (float)(progressSum / progressTarget);

    if (_requestsActive != 0) {
        [_progressView setProgress:progress animated:YES];
    }
    _bytesLabel.text = [NSString stringWithFormat:@"%llu / %llu bytes (%.1f%%)", (unsigned long long)_bytesReceived, (unsigned long long)_bytesTotal, 100.0 * progress];
}

- (void)_didSquash
{
    _requestsSquashed++;
    [self _updateComplete];
}

#pragma mark - TNLRequestHydrater

- (void)tnl_requestOperation:(TNLRequestOperation *)op
              hydrateRequest:(id<TNLRequest>)request
                  completion:(TNLRequestHydrateCompletionBlock)complete
{
    if ([request isKindOfClass:[TAPIRequest class]]) {
        [[TAPIClient sharedInstance] tnl_requestOperation:op
                                           hydrateRequest:request
                                               completion:complete];
        return;
    }

    complete(nil, nil);
}

#pragma mark - TNLRequestAuthorizer

- (void)tnl_requestOperation:(TNLRequestOperation *)op
         authorizeURLRequest:(NSURLRequest *)URLRequest
                  completion:(TNLAuthorizeCompletionBlock)completion
{
    if ([op.originalRequest isKindOfClass:[TAPIRequest class]]) {
        [[TAPIClient sharedInstance] tnl_requestOperation:op
                                      authorizeURLRequest:URLRequest
                                               completion:completion];
        return;
    }

    completion(nil, nil);
}

#pragma mark - TNLRequestEventHandler

- (dispatch_queue_t)tnl_delegateQueueForRequestOperation:(TNLRequestOperation *)op
{
    return dispatch_get_main_queue();
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
      didTransitionFromState:(TNLRequestOperationState)oldState
                     toState:(TNLRequestOperationState)newState
{
    assert([NSThread isMainThread]);

    if (op != _initialOp) {
        if (TNLRequestOperationStateIsActive(newState) && TNLRequestOperationStateIdle == oldState) {
            NSLog(@"TRANS: %@ %@ -> %@", op, TNLRequestOperationStateToString(oldState), TNLRequestOperationStateToString(newState));
            _requestsActive++;
            [self _updateActive];
        } else if (TNLRequestOperationStateIsActive(oldState) && TNLRequestOperationStateIsFinal(newState)) {
            NSLog(@"TRANS: %@ %@ -> %@", op, TNLRequestOperationStateToString(oldState), TNLRequestOperationStateToString(newState));
            if (_requestsActive == 0) {
                // This never should happen
                NSLog(@"Underflow of _requestsActive!!");
                assert(false);
                return;
            }
            _requestsActive--;
            [self _updateActive];
        }
    }
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
       didReceiveURLResponse:(NSHTTPURLResponse *)response
{
    if (op != _initialOp) {
        const long long contentLength = [response tnl_expectedResponseBodySize];
        if (contentLength > 0) {
            _bytesTotal += (uint64_t)contentLength;
            [self _updateProgress];
        }
    }
}

#if !DOWNLOAD_IMAGES && NON_DOWNLOAD_IMAGES_CONSUMPTION_MODE == TNLResponseDataConsumptionModeChunkToDelegateCallback

- (void)tnl_requestOperation:(TNLRequestOperation *)op
              didReceiveData:(NSData *)data
{
    assert([NSThread isMainThread]);
    assert(op != _initialOp);
    if (op != _initialOp) {
        _bytesReceived += data.length;
        [self _updateProgress];
    }
}

#endif

- (void)tnl_requestOperation:(TNLRequestOperation *)op
   didUpdateDownloadProgress:(float)downloadProgress
{
    [self _updateProgress];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TNLResponse *)response
{
    assert([NSThread isMainThread]);

    if (op == _initialOp) {
        TAPISearchResponse *searchResponse = (id)response;

        _bytesTotal = 0;
        NSArray *results = [searchResponse imagesFromStatuesRemovingSensitiveImages:YES];
        _results = _results ? [_results arrayByAddingObjectsFromArray:results] : results;
        _initialOp = nil;

        if (searchResponse.nextResultsObject && _results.count < COUNT) {
            [self _continueLoadWithNextResultsObject:searchResponse.nextResultsObject];
            return;
        }

        _startTime = CFAbsoluteTimeGetCurrent();
        if (_results.count) {
            _operations = [[NSMutableArray alloc] initWithCapacity:_results.count];
            NSUInteger delay = 0;
            for (id<TAPIImageEntityModel> result in _results) {
                [self performSelector:@selector(_enqueueRequestWithImageEntity:)
                           withObject:result
                           afterDelay:(NSTimeInterval)delay * DELAY_BETWEEN_IMAGE_SCHEDULING];
                delay++;
            }
        } else {
            _progressView.backgroundColor = [UIColor colorWithRed:0.75 green:0.1 blue:0.1 alpha:0.0];
        }
    } else {
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSError *error;
        if ([response.info.temporarySavedFile moveToPath:tempPath error:&error]) {
            NSLog(@"Saved: %@", tempPath);
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL]; // keep it clean
        } else if (response.info.temporarySavedFile) {
            NSLog(@"Error Saving: %@", error ?: response.operationError ?: [NSString stringWithFormat:@"HTTP %zd", response.info.statusCode]);
        }

#if DOWNLOAD_IMAGES || NON_DOWNLOAD_IMAGES_CONSUMPTION_MODE == TNLResponseDataConsumptionModeStoreInMemory
        if (200 == response.info.statusCode) {
            const SInt64 contentLength = response.metrics.attemptMetrics.lastObject.metaData.responseContentLength;
            if (contentLength) {
                _bytesReceived += (op.downloadProgress * (double)contentLength);
                [self _updateProgress];
            }
        }
#endif

        [self _dequeueRunningRequestWithResponse:response];
    }
}

#pragma mark - UIViewController

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end

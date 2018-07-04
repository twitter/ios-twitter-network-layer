//
//  TNLXThirdViewController.m
//  TwitterNetworkLayer
//
//  Created on 8/23/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

#import "TAPI.h"

#import "TNLXAppDelegate.h"
#import "TNLXMultipartFormData.h"
#import "TNLXPlaygroundViewController.h"

@import UIKit;

#define DOWNLOAD_URL @"http://speedtest.reliableservers.com/100MBtest.bin"

@interface Dummy : NSObject
- (id)URLSessionTaskOperation;
- (id)URLSession;
@end

#define TWEET_ID 523495208437424128LL

// #define TIMEOUT_VALUE (5)

typedef void(^TNLXCompletionBlock)(TNLRequestOperation *op, TNLResponse *response);

static /*not const*/ BOOL USE_CALLBACK_REDIRECT_POLICIES = YES;

typedef NS_ENUM(NSInteger, TNLXRedirectTestPolicy)
{
    TNLXRedirectTestPolicyCallbackNoRedirect,
    TNLXRedirectTestPolicyCallbackShortendedURLRedirect,
    TNLXRedirectTestPolicyCallbackAllRedirects,

    TNLXRedirectTestPolicyAutoNoRedirect,
    TNLXRedirectTestPolicyAutoRedirect,
    TNLXRedirectTestPolicyAutoRedirectCancelAfter1,
};

@interface TNLXRedirectTestObject : NSObject <TNLRequestDelegate>

@property (nonatomic, copy) TNLRequestConfiguration *config;
@property (nonatomic) TNLXRedirectTestPolicy redirectPolicy;
@property (nonatomic) NSUInteger redirectCount;
@property (nonatomic, copy) TNLXCompletionBlock completionBlock;
@property (nonatomic) id<TNLRequest> request;

- (void)start;

@end

@interface TNLXPlaygroundViewController () <TNLRequestDelegate, NSURLConnectionDataDelegate>
{
    IBOutlet UIButton *_multiSubmitButton;
    IBOutlet UIButton *_favButton;
    IBOutlet UIButton *_unfavButton;
    IBOutlet UIButton *_loadFileButton;
    IBOutlet UIButton *_cancelFileButton;
    IBOutlet UIButton *_httpTestButton;
    IBOutlet UIButton *_httpsTwitterTestButton;
    IBOutlet UIButton *_goWithRedirectsButton;
    IBOutlet UIButton *_goWithoutRedirectsButton;
    IBOutlet UIButton *_goWithOnlyShortlinkRedirects;
    IBOutlet UIProgressView *_multiProgressView;
    IBOutlet UIProgressView *_fileProgressView;
    IBOutlet UITextField *_httpTestField;
    IBOutlet UITextField *_customURLField;
    IBOutlet UILabel *_commsStatusField;

    TNLRequestOperationQueue *_queue;
    TNLRequestOperation *_currentOperation;
    NSString *_fileDestination;
    TNLRequestOperation *_fileDownloadOp;
    NSURLConnection *_fileDownloadConnection;
    NSURLResponse *_fileDownloadConnectionResponse;
    long long _fileDownloadConnectionLoadedBytes;
    NSString *_sessionId;
    NSUInteger _taskId;
}

@end

@implementation TNLXPlaygroundViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        [self prep];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self prep];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)prep
{
    if (_fileDestination) {
        return;
    }

    _fileDestination = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"DownloadFolder/LargeFileDownload.bin"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[_fileDestination stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    _queue = [[TNLRequestOperationQueue alloc] initWithIdentifier:NSStringFromClass([self class]).lowercaseString];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backgroundRequestDidDownloadNotification:) name:TNLBackgroundRequestOperationDidCompleteNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _multiSubmitButton.layer.borderWidth = 1;
    _multiSubmitButton.layer.borderColor = _multiSubmitButton.tintColor.CGColor;
    _favButton.layer.borderWidth = 1;
    _favButton.layer.borderColor = _favButton.tintColor.CGColor;
    _unfavButton.layer.borderWidth = 1;
    _unfavButton.layer.borderColor = _unfavButton.tintColor.CGColor;
    _loadFileButton.layer.borderWidth = 1;
    _loadFileButton.layer.borderColor = _loadFileButton.tintColor.CGColor;
    _cancelFileButton.layer.borderWidth = 1;
    _cancelFileButton.layer.borderColor = _cancelFileButton.tintColor.CGColor;
    _httpTestButton.layer.borderWidth = 1;
    _httpTestButton.layer.borderColor = _httpTestButton.tintColor.CGColor;
    _httpsTwitterTestButton.layer.borderWidth = 1;
    _httpsTwitterTestButton.layer.borderColor = _httpsTwitterTestButton.tintColor.CGColor;
    _goWithOnlyShortlinkRedirects.layer.borderWidth = 1;
    _goWithOnlyShortlinkRedirects.layer.borderColor = _goWithOnlyShortlinkRedirects.tintColor.CGColor;
    _goWithoutRedirectsButton.layer.borderWidth = 1;
    _goWithoutRedirectsButton.layer.borderColor = _goWithoutRedirectsButton.tintColor.CGColor;
    _goWithRedirectsButton.layer.borderWidth = 1;
    _goWithRedirectsButton.layer.borderColor = _goWithRedirectsButton.tintColor.CGColor;

    _multiProgressView.progress = 0;
    _fileProgressView.progress = 0;
    if ([[NSFileManager defaultManager] fileExistsAtPath:_fileDestination]) {
        _fileProgressView.progress = 1;
        _fileProgressView.tintColor = [UIColor greenColor];
        _loadFileButton.enabled = NO;
        _cancelFileButton.enabled = YES;
    } else {
        _fileProgressView.progress = 0;
        _fileProgressView.tintColor = [UIColor blueColor];
        _loadFileButton.enabled = YES;
        _cancelFileButton.enabled = NO;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_communicationStatusDidUpdate:)
                                                 name:TNLXCommunicationStatusUpdatedNotification
                                               object:nil];
    _commsStatusField.text = APP_DELEGATE.communicationStatusDescription;
}

- (void)_communicationStatusDidUpdate:(NSNotification *)note
{
    NSString *status = note.userInfo[@"description"] ?: APP_DELEGATE.communicationStatusDescription;
    _commsStatusField.text = status;
}

- (IBAction)goWithRedirects:(id)sender
{
    [self goWithRedirectPolicy:USE_CALLBACK_REDIRECT_POLICIES ? TNLXRedirectTestPolicyCallbackAllRedirects : TNLXRedirectTestPolicyAutoRedirect];
}

- (IBAction)goWithNoRedirects:(id)sender
{
    [self goWithRedirectPolicy:USE_CALLBACK_REDIRECT_POLICIES ? TNLXRedirectTestPolicyCallbackNoRedirect : TNLXRedirectTestPolicyAutoNoRedirect];
}

- (IBAction)goWithOnlyShortURLRedirects:(id)sender
{
    [self goWithRedirectPolicy:USE_CALLBACK_REDIRECT_POLICIES ? TNLXRedirectTestPolicyCallbackShortendedURLRedirect : TNLXRedirectTestPolicyAutoRedirectCancelAfter1];
}

- (void)goWithRedirectPolicy:(TNLXRedirectTestPolicy)redirectPolicy
{
    _goWithOnlyShortlinkRedirects.enabled = NO;
    _goWithoutRedirectsButton.enabled = NO;
    _goWithRedirectsButton.enabled = NO;

    TNLXRedirectTestObject *testObj = [[TNLXRedirectTestObject alloc] init];
    testObj.redirectPolicy = redirectPolicy;
    testObj.request = [TNLHTTPRequest GETRequestWithURL:[NSURL URLWithString:_customURLField.text]
                                       HTTPHeaderFields:nil];
    testObj.completionBlock = ^(TNLRequestOperation *operation, TNLResponse *response) {
        self->_goWithOnlyShortlinkRedirects.enabled = YES;
        self->_goWithoutRedirectsButton.enabled = YES;
        self->_goWithRedirectsButton.enabled = YES;

        [[[UIAlertView alloc] initWithTitle:@"Response"
                                    message:[NSString stringWithFormat:@"Redirect Count: %tu\nHeaders: %@\nMetrics: %@", response.metrics.redirectCount, response.info.allHTTPHeaderFields, response.metrics]
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    };
    [testObj start];
}

- (void)fileDownloadComplete:(BOOL)success
{
    [_fileProgressView setProgress:1.0 animated:YES];
    _fileProgressView.progressTintColor = success ? [UIColor greenColor] : [UIColor redColor];
    _loadFileButton.enabled = !success;
    _cancelFileButton.enabled = success;
    _fileDownloadOp = nil;
}

- (void)fileDownloadStarting
{
    [_fileProgressView setProgress:0 animated:NO];
    _fileProgressView.progressTintColor = [UIColor blueColor];
    _loadFileButton.enabled = NO;
    _cancelFileButton.enabled = YES;
}

- (IBAction)fileClear:(id)sender
{
    [[NSFileManager defaultManager] removeItemAtPath:_fileDestination error:NULL];
    [_fileProgressView setProgress:0 animated:NO];
    _fileProgressView.progressTintColor = [UIColor blueColor];
    _loadFileButton.enabled = YES;
    _cancelFileButton.enabled = NO;
    [_fileDownloadOp cancelWithSource:@"Clear"];
    _fileDownloadOp = nil;
    [_fileDownloadConnection cancel];
    _fileDownloadConnection = nil;
    _fileDownloadConnectionResponse = nil;
    _fileDownloadConnectionLoadedBytes = 0;
}

- (IBAction)fileDownload:(id)sender
{
    assert(!_fileDownloadOp);
    TNLMutableRequestConfiguration * config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.idleTimeout = 10;
    config.attemptTimeout = NSTimeIntervalSince1970;
    config.operationTimeout = NSTimeIntervalSince1970;
//    config.executionMode = TNLRequestExecutionModeBackground;
//    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
//    config.allowsCellularAccess = NO;

    _fileDownloadOp = [TNLRequestOperation operationWithURL:[NSURL URLWithString:DOWNLOAD_URL]
                                              configuration:config
                                                   delegate:self];

    [self fileDownloadStarting];
    [_queue enqueueRequestOperation:_fileDownloadOp];
}

- (IBAction)fileDownload_NSURLConnection_disabled:(id)sender
{
    assert(!_fileDownloadConnection);

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    request.URL = [NSURL URLWithString:DOWNLOAD_URL];
    request.timeoutInterval = 10;

    _fileDownloadConnection = [[NSURLConnection alloc] initWithRequest:request
                                                              delegate:self
                                                      startImmediately:NO];
    [_fileDownloadConnection setDelegateQueue:[NSOperationQueue mainQueue]];
    [self fileDownloadStarting];
    [_fileDownloadConnection start];
}

- (void)didEnterBackground:(NSNotification *)note
{
//    if (_fileDownloadOp) {
//        NSUInteger *pointer = NULL;
//        NSUInteger i = *pointer;
//        i++;
//    }
    NSLog(@"Background Timer Remaining: %@s", @([UIApplication sharedApplication].backgroundTimeRemaining));
}

- (void)backgroundRequestDidDownloadNotification:(NSNotification *)note
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:note waitUntilDone:NO];
        return;
    }

    NSURLRequest *request = note.userInfo[TNLBackgroundRequestURLRequestKey];
    TNLResponse *response = note.userInfo[TNLBackgroundRequestResponseKey];
    NSUInteger taskId = [(NSNumber *)note.userInfo[TNLBackgroundRequestURLSessionTaskIdentifierKey] unsignedIntegerValue];
    NSString *sessionId = note.userInfo[TNLBackgroundRequestURLSessionConfigurationIdentifierKey];

    NSLog(@"[BG_DOWNLOAD] - %@", note);

    if (taskId == _taskId) {
        if ([sessionId isEqualToString:_sessionId]) {
            NSURL *originalURL = _fileDownloadOp.hydratedRequest.URL ?: ([_fileDownloadOp.originalRequest respondsToSelector:@selector(URL)] ? [(id)_fileDownloadOp.originalRequest URL] : nil);
            if ([request.URL.absoluteString isEqualToString:originalURL.absoluteString]) {
                NSError *error;
                BOOL success = response.info.statusCode == 200 && [response.info.temporarySavedFile moveToPath:_fileDestination error:&error];
                if (error) {
                    NSLog(@"%@ %@", NSStringFromSelector(_cmd), error);
                }
                [self fileDownloadComplete:success];
            }
        }
    }
}

- (void)complete:(BOOL)success
{
    [_multiProgressView setProgress:1.0 animated:YES];
    _multiProgressView.progressTintColor = success ? [UIColor greenColor] : [UIColor redColor];
    _multiSubmitButton.enabled = YES;
    _favButton.enabled = YES;
    _unfavButton.enabled = YES;
    _currentOperation = nil;
}

- (void)willStart
{
    [_multiProgressView setProgress:0 animated:NO];
    _unfavButton.enabled = NO;
    _favButton.enabled = NO;
    _multiSubmitButton.enabled = NO;
    _multiProgressView.progressTintColor = [UIColor blueColor];
}

- (IBAction)multiSubmit:(UIButton *)sender
{
    [self willStart];

    UIImage *image = [UIImage imageNamed:@"first"];
    NSData *jpegData = UIImageJPEGRepresentation(image, .05f);

    TAPIUploadMediaRequest *request = [[TAPIUploadMediaRequest alloc] initWithImageData:jpegData];

    _currentOperation = [[TAPIClient sharedInstance] startRequest:request
                                                       completion:^(TAPIUploadMediaResponse *response) {
                                                           [self complete:response.didSucceed];
                                                       }];
}

- (IBAction)fav:(id)sender
{
    [self willStart];

    TAPIClient *client = [TAPIClient sharedInstance];
    TAPIFavoriteCreateRequest *favRequest = [[TAPIFavoriteCreateRequest alloc] initWithStatusID:TWEET_ID];
    _currentOperation = [client startRequest:favRequest
                                  completion:^(TAPIFavoriteResponse *response) {
                                      [self complete:response.didSucceed];
                                  }];
}

- (IBAction)unfav:(id)sender
{
    [self willStart];

    TAPIClient *client = [TAPIClient sharedInstance];
    TAPIFavoriteDestroyRequest *unfavRequest = [[TAPIFavoriteDestroyRequest alloc] initWithStatusID:TWEET_ID];
    _currentOperation = [client startRequest:unfavRequest
                                  completion:^(TAPIFavoriteResponse *response) {
                                      [self complete:response.didSucceed];
                                  }];
}

- (IBAction)kill:(id)sender
{
    NSUInteger *pointer = NULL;
    NSUInteger i = *pointer;
    i++;
}

- (IBAction)testHTTP:(id)sender
{
    [_httpTestField resignFirstResponder];
    _httpTestButton.enabled = NO;
    NSInteger code = [_httpTestField.text integerValue];
    NSString *URLString = [NSString stringWithFormat:@"http://httpbin.org/status/%td", code];
    TNLRequestOperation *op = [TNLRequestOperation operationWithURL:[NSURL URLWithString:URLString]
                                                         completion:^(TNLRequestOperation *innerOp, TNLResponse *response) {
        self->_httpTestButton.enabled = YES;
        [[[UIAlertView alloc] initWithTitle:@"HTTP Response" message:[NSString stringWithFormat:@"Status Code: %td", response.info.statusCode] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
}

- (IBAction)testHTTPSTwitter:(id)sender
{
    [self testTwitter];
}

- (void)testTwitter
{
    _httpsTwitterTestButton.enabled = NO;
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];

//    static NSInteger swap = 0;
//    swap++;
//    switch (swap % 4) {
//        case 1:
//            config.URLCache = [NSURLCache tnl_sharedURLCacheProxy];
//            break;
//        case 2:
//            config.URLCache = [NSURLCache tnl_impotentURLCache];
//            break;
//        case 3:
//            config.URLCache = [NSURLCache sharedURLCache];
//            break;
//        case 0:
//        default:
//            config.URLCache = nil;
//            break;
//    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.twitter.com"]];

    TNLXCompletionBlock block = ^(TNLRequestOperation *innerOp, TNLResponse *response) {
        assert([NSThread isMainThread]);
        self->_httpsTwitterTestButton.enabled = YES;
        [[[UIAlertView alloc] initWithTitle:@"HTTP Response"
                                    message:[NSString stringWithFormat:@"Metrics: %@", response.metrics]
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        NSLog(@"(%zi) (CL: %@) %@ %@", response.info.statusCode, [response.info valueForResponseHeaderField:@"Content-Length"], response.operationError ?: @"", response.metrics);
        // TLSLogDebug(NSStringFromClass([self class]), @"Headers: %@", response.info.allHTTPHeaderFields);
    };

    TNLXRedirectTestObject *testObj = [[TNLXRedirectTestObject alloc] init];
    testObj.request = request;
    testObj.redirectPolicy = 0; // to test without redirects set this to -1
    testObj.completionBlock = block;
    testObj.config = config;
    [testObj start];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
              hydrateRequest:(id<TNLRequest>)request
                  completion:(TNLRequestHydrateCompletionBlock)complete
{
    if (op == _fileDownloadOp) {
        complete(nil, nil);
        return;
    }

    assert([request isKindOfClass:[TNLXMultipartFormDataRequest class]]);

#if TIMEOUT_VALUE
    sleep(TIMEOUT_VALUE * 2);
#endif

    NSError *error = nil;
    request = [(TNLXMultipartFormDataRequest *)request generateRequestWithUploadFormat:TNLXMultipartFormDataUploadFormatFile
                                                                                 error:&error];
    complete(request, error);
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
      didTransitionFromState:(TNLRequestOperationState)oldState
                     toState:(TNLRequestOperationState)newState
{
    if (op == _fileDownloadOp) {
//        if (newState == TNLRequestOperationStateRunning) {
//            [(NSURLSession *)[(id)[(id)op URLSessionTaskOperation] URLSession] getTasksWithCompletionHandler:^(NSArray *nt, NSArray *ut, NSArray *dt) {
//                NSLog(@"\ndata: %@\nupload: %@\ndownload: %@", nt, ut, dt);
//            }];
//        }
        return;
    }

    if (newState == TNLRequestOperationStateRunning) {
#if TIMEOUT_VALUE
        sleep(TIMEOUT_VALUE * 2);
#endif
    }
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
        didStartBackgroundRequestWithURLSessionTaskIdentifier:(NSUInteger)taskId
        URLSessionConfigurationIdentifier:(NSString *)configId
        URLSessionSharedContainerIdentifier:(NSString *)sharedContainerIdentifier
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (op != self->_fileDownloadOp) {
            return;
        }

        self->_sessionId = configId;
        self->_taskId = taskId;
    });
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TNLResponse *)response
{
    assert([NSThread isMainThread]);

    NSURL *originalURL = [op.originalRequest respondsToSelector:@selector(URL)] ? [(id)op.originalRequest URL] : nil;
    if ([originalURL.absoluteString isEqualToString:DOWNLOAD_URL]) {
        NSLog(@"[BG_DOWNLOAD] - %@ %@", op.originalRequest, response);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"BG Download"
                                                        message:[NSString stringWithFormat:@"%@", response]
                                                       delegate:NULL
                                              cancelButtonTitle:@"Close"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }

    NSLog(@"%@ %@ %@ %@", NSStringFromSelector(_cmd), op, response, response.metrics);
    [self complete:!response.operationError && 200 == response.info.statusCode];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didUpdateUploadProgress:(float)uploadProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (op == self->_fileDownloadOp) {
            return;
        }

        [self->_multiProgressView setProgress:uploadProgress animated:YES];
    });
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
   didUpdateDownloadProgress:(float)downloadProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (op != self->_fileDownloadOp) {
            return;
        }

        [self->_fileProgressView setProgress:downloadProgress animated:YES];
    });
}

#pragma mark Connection

- (void)connection:(NSURLConnection *)connection
    didReceiveData:(NSData *)data
{
    _fileDownloadConnectionLoadedBytes += data.length;
    _fileProgressView.progress = (float)((double)_fileDownloadConnectionLoadedBytes / (double)_fileDownloadConnectionResponse.expectedContentLength);
}

- (void)connection:(NSURLConnection *)connection
didReceiveResponse:(NSURLResponse *)response
{
    _fileDownloadConnectionResponse = response;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self _connection:connection
          didFinishedWithResponse:_fileDownloadConnectionResponse
          error:nil];
}

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error
{
    [self _connection:connection
          didFinishedWithResponse:_fileDownloadConnectionResponse
          error:error];
}

- (void)_connection:(NSURLConnection *)connection
        didFinishedWithResponse:(NSURLResponse *)response
        error:(NSError *)error
{
    NSLog(@"[BG_DOWNLOAD] - %@ %@", connection.originalRequest, response);
    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
    if (response) {
        info[@"response"] = response;
    }
    if (error) {
        info[@"error"] = error;
    }
    info[@"URL"] = connection.originalRequest.URL;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"BG Download"
                                                    message:[NSString stringWithFormat:@"%@", info]
                                                   delegate:nil
                                          cancelButtonTitle:@"Close"
                                          otherButtonTitles:nil];
    [alert show];
}

@end

@implementation TNLXRedirectTestObject

- (void)start
{
    TNLMutableRequestConfiguration *config = [self.config mutableCopy] ?: [TNLMutableRequestConfiguration defaultConfiguration];
    switch (self.redirectPolicy) {
        case TNLXRedirectTestPolicyAutoNoRedirect:
            config.redirectPolicy = TNLRequestRedirectPolicyDontRedirect;
            break;
        case TNLXRedirectTestPolicyAutoRedirect:
        case TNLXRedirectTestPolicyAutoRedirectCancelAfter1:
            config.redirectPolicy = TNLRequestRedirectPolicyDoRedirect;
            break;
        case TNLXRedirectTestPolicyCallbackNoRedirect:
        case TNLXRedirectTestPolicyCallbackAllRedirects:
        case TNLXRedirectTestPolicyCallbackShortendedURLRedirect:
            config.redirectPolicy = TNLRequestRedirectPolicyUseCallback;
            break;
    }
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:self.request
                                                          configuration:config
                                                               delegate:self];
    op.context = self;
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     willRedirectFromRequest:(NSURLRequest<TNLRequest> *)fromRequest
                withResponse:(NSHTTPURLResponse *)response
                   toRequest:(NSURLRequest<TNLRequest> *)providedRequest
                  completion:(TNLRequestRedirectCompletionBlock)completionBlock
{
    NSURLRequest *toRequest = providedRequest;
    TNLXRedirectTestPolicy policy = self.redirectPolicy;
    if (policy == TNLXRedirectTestPolicyCallbackNoRedirect) {
        toRequest = nil;
    } else if (policy == TNLXRedirectTestPolicyCallbackShortendedURLRedirect) {
        if (toRequest.URL.host.length > 8) {
            toRequest = nil;
        } else {
            NSArray *components = toRequest.URL.pathComponents;
            if (components.count > 2) {
                toRequest = nil;
            } else if ([(NSString *)components.lastObject length] > 16) {
                toRequest = nil;
            }
        }
    }
    if (toRequest) {
        NSLog(@"Redirecting to %@", toRequest.URL);
    } else {
        NSLog(@"Stopping redirect (was %@)", providedRequest.URL);
    }
    completionBlock(toRequest);
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
        didRedirectFromURLRequest:(NSURLRequest *)fromRequest
        toURLRequest:(NSURLRequest *)toRequest
{
    self.redirectCount++;
    if (self.redirectCount > 1 && self.redirectPolicy == TNLXRedirectTestPolicyAutoRedirectCancelAfter1) {
        [op cancelWithSource:@"TNLXRedirectTestPolicyAutoRedirectCancelAfter1"];
    }
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
        didCompleteWithResponse:(TNLResponse *)response
{
    TNLXCompletionBlock block = self.completionBlock;
    self.completionBlock = nil;
    if (block) {
        block(op, response);
    }
}

@end

//
//  TNLRequestOperationTest.m
//  TwitterNetworkLayer
//
//  Created on 11/12/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#include <pthread.h>

#import "NSDictionary+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLGlobalConfiguration_Project.h"
#import "TNLHTTPRequest.h"
#import "TNLPseudoURLProtocol.h"
#import "TNLRequestDelegate.h"
#import "TNLRequestOperation_Project.h"
#import "TNLRequestOperationCancelSource.h"
#import "TNLRequestOperationQueue_Project.h"
#import "TNLTemporaryFile_Project.h"

@import ObjectiveC.runtime;
#if TARGET_OS_IPHONE // == IOS + WATCHOS + TVOS
@import UIKit.UIApplication; // for notification names
#endif
@import XCTest;

// unit tests should never hit the network for CI.  can turn this to 0 to hit the network for local testing if desired (be careful!)
#define RUN_TESTS_WITH_CANNED_RESPONSES 1

// background requests cannot be run from unit tests, so this will stay 0
#define RUN_BACKGROUND_REQUESTS 0

#define kBODY_DICTIONARY @{@"body":@"this is the body"}

static NSError *CoersedOperationError(NSError *error);
static NSError *CoersedOperationError(NSError *error)
{
    if ([error.domain isEqualToString:TNLErrorDomain] && error.code == TNLErrorCodeRequestOperationInvalidHydratedRequest) {
        error = error.userInfo[NSUnderlyingErrorKey];
    }
    return error;
}

#if TARGET_OS_IPHONE // == IOS + WATCHOS + TVOS
@interface FakeApplication : NSObject
@property (nonatomic) UIApplicationState applicationState;
- (instancetype)init;
@end

static FakeApplication *sFakeApplication = nil;

static void FireFakeApplicationNotification(NSString *notificationName, NSTimeInterval delay);
static void FireFakeApplicationNotification(NSString *notificationName, NSTimeInterval delay)
{
    UIApplicationState newState = sFakeApplication.applicationState;
    BOOL updateStateAfterNotification = NO;
    if ([notificationName isEqualToString:UIApplicationWillResignActiveNotification]) {
        updateStateAfterNotification = YES;
        newState = UIApplicationStateInactive;
    } else if ([notificationName isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        updateStateAfterNotification = YES;
        newState = UIApplicationStateInactive;
    } else if ([notificationName isEqualToString:UIApplicationDidBecomeActiveNotification]) {
        newState = UIApplicationStateActive;
    } else if ([notificationName isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        newState = UIApplicationStateBackground;
    }

    UIApplication *application = (id)sFakeApplication;
    dispatch_block_t block = ^{
        if (!updateStateAfterNotification) {
            sFakeApplication.applicationState = newState;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:application];
        if (updateStateAfterNotification) {
            sFakeApplication.applicationState = newState;
        }
    };
    if (delay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
    } else {
        block();
    }
}

@implementation FakeApplication
- (instancetype)init
{
    if (self = [super init]) {
        _applicationState = UIApplicationStateBackground;
    }
    return self;
}
@end
#endif // TARGET_OS_IPHONE

@interface TestJSONResponse : TNLResponse
@property (nonatomic, readonly) NSDictionary *result;
@property (nonatomic, readonly) NSError *jsonParseError;
@property (nonatomic, readonly) BOOL responseBodyWasInFile;
@end

@interface TestTNLRequestDelegate : NSObject <TNLRequestDelegate>
@property (atomic, readonly) NSArray<NSString *> *observedCallbacks;
@end

typedef void(^TestCallbackBlock)(TestJSONResponse *response);

@interface TNLRequestOperationTest : XCTestCase <TNLRequestDelegate>
{
    NSMutableArray *_registeredEndpoints;
    dispatch_queue_t _delegateQueue;
}

@property (atomic) BOOL responseWasReceived;
@property (atomic) BOOL attemptDidComplete;
@property (atomic) NSNumber *requestClogDuration;

- (void)cleanupPseudoProtocol;
- (void)unregisterRequest:(TNLHTTPRequest *)request;
- (void)registerRequest:(TNLHTTPRequest *)request args:(NSDictionary *)args;
- (TNLMutableRequestConfiguration *)config;
- (TNLMutableHTTPRequest *)httpBinRequest:(NSDictionary *)args;
- (NSData *)uploadData;
- (NSString *)uploadFile;
- (NSInputStream *)uploadStream;
- (TNLRequestOperation *)executeRequest:(TNLHTTPRequest *)request config:(TNLRequestConfiguration *)config;
- (void)performRequest:(TNLHTTPRequest *)request config:(TNLRequestConfiguration *)config args:(NSDictionary *)args callback:(TestCallbackBlock)callback;

@end

@implementation TNLRequestOperationTest

+ (void)setUp
{
    [super setUp];
#if TARGET_OS_IPHONE // == IOS + WATCHOS + TVOS
    (void)[TNLGlobalConfiguration sharedInstance];
    sFakeApplication = [[FakeApplication alloc] init];
    sFakeApplication.applicationState = UIApplicationStateActive;
    FireFakeApplicationNotification(UIApplicationDidFinishLaunchingNotification, 0);
#endif
}

+ (void)tearDown
{
#if TARGET_OS_IPHONE // == IOS + WATCHOS + TVOS
    sFakeApplication.applicationState = UIApplicationStateActive;
    FireFakeApplicationNotification(UIApplicationDidFinishLaunchingNotification, 0);
    sFakeApplication = nil;
#endif
    [super tearDown];
}

- (void)setUp
{
    [super setUp];
    _registeredEndpoints = [NSMutableArray array];
    _delegateQueue = dispatch_queue_create("TNLRequestOperationTest.delegate.queue", DISPATCH_QUEUE_SERIAL);
}

- (void)tearDown
{
    _delegateQueue = nil;
    [self cleanupPseudoProtocol];
    self.attemptDidComplete = NO;
    self.responseWasReceived = NO;
    [super tearDown];
}

- (void)cleanupPseudoProtocol
{
    for (NSURL *url in _registeredEndpoints) {
        [TNLPseudoURLProtocol unregisterEndpoint:url];
    }
    [_registeredEndpoints removeAllObjects];
}

- (void)unregisterRequest:(TNLHTTPRequest *)request
{
    [TNLPseudoURLProtocol unregisterEndpoint:request.URL];
    [_registeredEndpoints removeObject:request.URL];
}

- (void)registerRequest:(TNLHTTPRequest *)request args:(NSDictionary *)args
{
#if RUN_TESTS_WITH_CANNED_RESPONSES

    NSURL *endpoint = request.URL;
    BOOL hasBody = request.HTTPBody || request.HTTPBodyFilePath || request.HTTPBodyStream;

    NSMutableDictionary *headers = [request.allHTTPHeaderFields mutableCopy];
    headers[@"Host"] = endpoint.host;
    if (hasBody) {
        headers[@"Content-Length"] = @(self.uploadData.length).stringValue;
        headers[@"Content-Type"] = TNLHTTPContentTypeJSON;
    }
    NSDictionary *responseBodyJSON = @{ @"args" : args ?: @{}, @"headers" : headers, @"url" : endpoint.absoluteString, @"json" : (hasBody) ? kBODY_DICTIONARY : [NSNull null] };
    NSData *body = [NSJSONSerialization dataWithJSONObject:responseBodyJSON options:0 error:NULL];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:endpoint statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Content-Type" : @"application/json" }];

    [TNLPseudoURLProtocol registerURLResponse:response body:body withEndpoint:endpoint];
    [_registeredEndpoints addObject:endpoint];

#endif // RUN_TESTS_WITH_CANNED_RESPONSES
}

- (TNLMutableRequestConfiguration *)config
{
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.URLCache = nil;
    config.cachePolicy = NSURLCacheStorageNotAllowed;
#if RUN_TESTS_WITH_CANNED_RESPONSES
    config.protocolOptions = TNLRequestProtocolOptionPseudo;
#endif // RUN_TESTS_WITH_CANNED_RESPONSES
    return config;
}

- (TNLMutableHTTPRequest *)httpBinRequest:(NSDictionary *)args
{
    NSString *params = [[[TNLParameterCollection alloc] initWithDictionary:args] URLEncodedStringValueWithOptions:TNLURLEncodingOptionsNone];
    NSString *urlString = [NSString stringWithFormat:@"http://httpbin.org/%@", args[@"method"] ?: @"get"];
    if (params.length) {
        urlString = [urlString stringByAppendingFormat:@"?%@", params];
    }
    NSURL *endpoint = [NSURL URLWithString:urlString];
    TNLMutableHTTPRequest *request = [[TNLMutableHTTPRequest alloc] initWithURL:endpoint HTTPMethodValue:TNLHTTPMethodUnknown HTTPHeaderFields:@{ @"TNL-Version" : TNLVersion() } HTTPBody:nil HTTPBodyStream:nil HTTPBodyFilePath:nil];
    return request;
}

- (NSData *)uploadData
{
    static NSData *sData = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sData = [NSJSONSerialization dataWithJSONObject:kBODY_DICTIONARY options:0 error:NULL];
    });
    return sData;
}

- (NSString *)uploadFile
{
    static NSString *sFile;
    static dispatch_once_t sOnce;
    dispatch_once(&sOnce, ^{
        NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"com.twitter.tnl.request.operation.test.json"];
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
        if ([self.uploadData writeToFile:filePath atomically:YES]) {
            sFile = filePath;
        }
    });
    return sFile;
}

- (NSInputStream *)uploadStream
{
    NSInputStream *inputStream = nil;
    NSString *path = self.uploadFile;
    if (path) {
        inputStream = [NSInputStream inputStreamWithFileAtPath:self.uploadFile];
    } else {
        NSData *data = self.uploadData;
        if (data) {
            inputStream = [NSInputStream inputStreamWithData:data];
        }
    }
    return inputStream;
}

- (TNLRequestOperation *)executeRequest:(TNLHTTPRequest *)request config:(TNLRequestConfiguration *)config
{
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request responseClass:[TestJSONResponse class] configuration:config delegate:self];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    return op;
}

- (void)performRequest:(TNLHTTPRequest *)request config:(TNLRequestConfiguration *)config args:(NSDictionary *)args callback:(TestCallbackBlock)callback
{
    [self registerRequest:request args:args];
    TNLRequestOperation *op = [self executeRequest:request config:config];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertTrue(self.responseWasReceived);
    XCTAssertTrue(self.attemptDidComplete);
    TestJSONResponse *response = (id)op.response;
    if (callback) {
        callback(response);
    }
    [self unregisterRequest:request];
    self.responseWasReceived = NO;
    self.attemptDidComplete = NO;
}

#pragma mark - TNLRequestDelegate

- (void)tnl_requestOperation:(TNLRequestOperation *)op hydrateRequest:(id<TNLRequest>)request completion:(TNLRequestHydrateCompletionBlock)complete
{
    NSNumber *sleepDuration = self.requestClogDuration;
    if (sleepDuration) {
        [NSThread sleepForTimeInterval:[sleepDuration doubleValue]];
    }
    complete(request, nil);
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteWithResponse:(TNLResponse *)response
{
    self.responseWasReceived = YES;
    XCTAssertTrue(self.attemptDidComplete, @"%@", response);
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteAttemptWithResponse:(TNLResponse *)response disposition:(TNLAttemptCompleteDisposition)disposition
{
    self.attemptDidComplete = YES;
    XCTAssertFalse(self.responseWasReceived, @"%@", response);
}

- (dispatch_queue_t)tnl_delegateQueueForRequestOperation:(TNLRequestOperation *)op
{
    return _delegateQueue;
}

- (dispatch_queue_t)tnl_completionQueueForRequestOperation:(TNLRequestOperation *)op
{
    return _delegateQueue;
}

#pragma mark - Tests

- (void)testGET
{
    NSDictionary *args = @{@"method":@"get"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodGET;
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

#if RUN_BACKGROUND_REQUESTS

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#endif // RUN_BACKGROUND_REQUESTS

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPOSTWithoutBody
{
    NSDictionary *args = @{@"method":@"post"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPOST;
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], [NSNull null]);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], [NSNull null]);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

#if RUN_BACKGROUND_REQUESTS

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], [NSNull null]);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#endif // RUN_BACKGROUND_REQUESTS

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPOSTWithData
{
    NSDictionary *args = @{@"method":@"post"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPOST;
    request.HTTPBody = self.uploadData;
    [request setValue:TNLHTTPContentTypeJSON forHTTPHeaderField:@"Content-Type"];
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPOSTWithStream
{
    NSDictionary *args = @{@"method":@"post"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPOST;
    request.HTTPBodyStream = self.uploadStream;
    [request setValue:TNLHTTPContentTypeJSON forHTTPHeaderField:@"Content-Type"];
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPOSTWithFile
{
    NSDictionary *args = @{@"method":@"post"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPOST;
    request.HTTPBodyFilePath = self.uploadFile;
    [request setValue:TNLHTTPContentTypeJSON forHTTPHeaderField:@"Content-Type"];
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

#if RUN_BACKGROUND_REQUESTS

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

#endif // RUN_BACKGROUND_REQUESTS

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPUTWithoutBody
{
    NSDictionary *args = @{@"method":@"put"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPUT;
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], [NSNull null]);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], [NSNull null]);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

#if RUN_BACKGROUND_REQUESTS

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], [NSNull null]);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#endif // RUN_BACKGROUND_REQUESTS

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPUTWithData
{
    NSDictionary *args = @{@"method":@"put"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPUT;
    request.HTTPBody = self.uploadData;
    [request setValue:TNLHTTPContentTypeJSON forHTTPHeaderField:@"Content-Type"];
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPUTWithStream
{
    NSDictionary *args = @{@"method":@"put"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPUT;
    request.HTTPBodyStream = self.uploadStream;
    [request setValue:TNLHTTPContentTypeJSON forHTTPHeaderField:@"Content-Type"];
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testPUTWithFile
{
    NSDictionary *args = @{@"method":@"put"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodPUT;
    request.HTTPBodyFilePath = self.uploadFile;
    [request setValue:TNLHTTPContentTypeJSON forHTTPHeaderField:@"Content-Type"];
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

#if RUN_BACKGROUND_REQUESTS

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)self.uploadData.length);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertEqualObjects(response.result[@"json"], kBODY_DICTIONARY);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

#endif // RUN_BACKGROUND_REQUESTS

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestHTTPBodyCannotBeSetForDownload);
    }];

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testDELETE
{
    NSDictionary *args = @{@"method":@"delete"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodDELETE;
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertFalse(response.responseBodyWasInFile);
    }];

    // Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result, @"Something happened: %@", response.operationError);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#if !RUN_TESTS_WITH_CANNED_RESPONSES

    // Background - Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeBackground;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        NSError *error = CoersedOperationError(response.operationError);
        XCTAssertEqualObjects(error.domain, TNLErrorDomain);
        XCTAssertEqual(error.code, TNLErrorCodeRequestInvalidBackgroundRequest);
    }];

#if RUN_BACKGROUND_REQUESTS

    // Background - Save to Disk
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeSaveToDisk;
    config.executionMode = TNLRequestExecutionModeInApp;

    [self performRequest:request config:config args:args callback:^(TestJSONResponse *response) {
        XCTAssertEqual(response.info.statusCode, 200);
        XCTAssertNotNil(response.result);
        XCTAssertEqualObjects([response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"TNL-Version"].firstObject, TNLVersion());
        XCTAssertEqual([[response.result[@"headers"] tnl_objectsForCaseInsensitiveKey:@"Content-Length"].firstObject integerValue], (NSInteger)0);
        XCTAssertEqualObjects(response.result[@"args"], args);
        XCTAssertTrue(response.responseBodyWasInFile);
    }];

#endif // RUN_BACKGROUND_REQUESTS

#endif // !RUN_TESTS_WITH_CANNED_RESPONSES
}

- (void)testCancelBeforeStart
{
    NSDictionary *args = @{@"method":@"get"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodGET;
    TNLMutableRequestConfiguration *config = self.config;

    // Normal
    config.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
    config.executionMode = TNLRequestExecutionModeInApp;

    __block TNLResponse *completedResponse;
    TNLRequestOperation *operation;

    completedResponse = nil;
    operation = [TNLRequestOperation operationWithRequest:request completion:^(TNLRequestOperation *op, TNLResponse *response) {
        completedResponse = response;
    }];
    [operation cancelWithSource:@"Early Cancel"];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3.0]];
    XCTAssertFalse(operation.isFinished);
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqualObjects(TNLErrorDomain, completedResponse.operationError.domain);
    XCTAssertEqual(TNLErrorCodeRequestOperationCancelled, completedResponse.operationError.code);

    completedResponse = nil;
    operation = [TNLRequestOperation operationWithRequest:request completion:^(TNLRequestOperation *op, TNLResponse *response) {
        completedResponse = response;
    }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation cancelWithSource:@"Early Cancel"];
    [operation waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqualObjects(TNLErrorDomain, completedResponse.operationError.domain);
    XCTAssertEqual(TNLErrorCodeRequestOperationCancelled, completedResponse.operationError.code);
}

- (TNLResponse *)_runCloggedCallback:(NSTimeInterval)lockedDuration
{
    BOOL oldShouldForceCrashOnCloggedCallback = [TNLGlobalConfiguration sharedInstance].shouldForceCrashOnCloggedCallback;
    NSTimeInterval oldCallbackTimeout = [TNLGlobalConfiguration sharedInstance].requestOperationCallbackTimeout;
    [TNLGlobalConfiguration sharedInstance].shouldForceCrashOnCloggedCallback = NO;
    [TNLGlobalConfiguration sharedInstance].requestOperationCallbackTimeout = 3.0;


    NSDictionary *args = @{@"method":@"get"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodGET;
    TNLMutableRequestConfiguration *config = self.config;
    TNLRequestOperation *op;

    // Register request
    op = [TNLRequestOperation operationWithRequest:request configuration:config delegate:self];
    [self registerRequest:request args:args];

    // Clog w/ sleep
    self.requestClogDuration = @(lockedDuration);

    // Run
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [self unregisterRequest:request];
    TNLResponse *response = op.response;

    // Reset global config
    [TNLGlobalConfiguration sharedInstance].shouldForceCrashOnCloggedCallback = oldShouldForceCrashOnCloggedCallback;
    [TNLGlobalConfiguration sharedInstance].requestOperationCallbackTimeout = oldCallbackTimeout;

    return response;
}

- (void)testCallbackClog1_NormalFailure
{
    TNLResponse *response = [self _runCloggedCallback:5.0];
    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationCallbackTimedOut);
    XCTAssertTrue([[response.operationError.userInfo[@"timeoutTags"] firstObject] hasPrefix:NSStringFromClass([self class])]);
}

#if TARGET_OS_IPHONE // == IOS + WATCHOS + TVOS

- (void)testCallbackClog2_ClogBackgroundForegroundUnclogSuccess
{
    FireFakeApplicationNotification(UIApplicationWillResignActiveNotification, 0.5);
    FireFakeApplicationNotification(UIApplicationDidBecomeActiveNotification, 5.0);
    TNLResponse *response = [self _runCloggedCallback:6.0];
    XCTAssertNil(response.operationError);
    XCTAssertNotNil(response);
}

- (void)testCallbackClog3_ClogBackgroundForegroundStillCloggedFailure
{
    FireFakeApplicationNotification(UIApplicationWillResignActiveNotification, 0.5);
    FireFakeApplicationNotification(UIApplicationDidBecomeActiveNotification, 5.0);
    TNLResponse *response = [self _runCloggedCallback:9.0];
    XCTAssertEqualObjects(response.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(response.operationError.code, TNLErrorCodeRequestOperationCallbackTimedOut);
    XCTAssertTrue([[response.operationError.userInfo[@"timeoutTags"] firstObject] hasPrefix:NSStringFromClass([self class])]);
}

#endif // TARGET_OS_IPHONE

- (void)testIdleTimeoutModes
{
    NSURL *URL = [NSURL URLWithString:@"https://www.idle.timeouts.com/dummy"];
    const NSTimeInterval latency = 3.0;
    const NSTimeInterval idleTimeout = 1.0;
    XCTAssert(latency > idleTimeout);
    TNLMutableHTTPRequest *request = [TNLMutableHTTPRequest GETRequestWithURL:URL HTTPHeaderFields:nil];
    request.HTTPMethodValue = TNLHTTPMethodGET;
    TNLMutableRequestConfiguration *config = self.config;
    config.idleTimeout = idleTimeout;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;
    @autoreleasepool {
        NSData *binaryData = [NSData dataWithContentsOfFile:[NSBundle bundleForClass:[self class]].executablePath];
        NSMutableData *responseData = [binaryData mutableCopy];
        const NSUInteger responseLength = 1000000;
        while (responseData.length < responseLength) {
            [responseData appendData:binaryData];
        }
        [responseData setLength:responseLength];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Content-Type" : @"application/octet-stream" }];
        TNLPseudoURLResponseConfig *responseConfig = [[TNLPseudoURLResponseConfig alloc] init];
        responseConfig.bps = 2000000;
        responseConfig.latency = (uint64_t)(latency * 1000.0);
        [TNLPseudoURLProtocol registerURLResponse:response body:responseData config:responseConfig withEndpoint:URL];
    }
    __block TNLResponse *completedResponse;
    TNLRequestOperation *operation;

    // Idle Timeout Includes Initial Connection
    [TNLGlobalConfiguration sharedInstance].idleTimeoutMode = TNLGlobalConfigurationIdleTimeoutModeEnabledIncludingInitialConnection;
    completedResponse = nil;
    operation = [TNLRequestOperation operationWithRequest:request configuration:config completion:^(TNLRequestOperation *op, TNLResponse *response) {
        completedResponse = response;
    }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqualObjects(completedResponse.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(completedResponse.operationError.code, TNLErrorCodeRequestOperationIdleTimedOut);
    XCTAssertGreaterThan(completedResponse.metrics.totalDuration, idleTimeout);
    NSTimeInterval withConnectionTimeoutDuration = completedResponse.metrics.totalDuration;
    NSLog(@"Idle Timeout Includes Initial Connection: %.3fs", completedResponse.metrics.totalDuration);

    // Idle Timeout Excludes Initial Connection
    [TNLGlobalConfiguration sharedInstance].idleTimeoutMode = TNLGlobalConfigurationIdleTimeoutModeEnabledExcludingInitialConnection;
    completedResponse = nil;
    operation = [TNLRequestOperation operationWithRequest:request configuration:config completion:^(TNLRequestOperation *op, TNLResponse *response) {
        completedResponse = response;
    }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqualObjects(completedResponse.operationError.domain, TNLErrorDomain);
    XCTAssertEqual(completedResponse.operationError.code, TNLErrorCodeRequestOperationIdleTimedOut);
    XCTAssertGreaterThan(completedResponse.metrics.totalDuration, latency);
    XCTAssertGreaterThan(completedResponse.metrics.totalDuration, withConnectionTimeoutDuration + latency);
    NSTimeInterval withoutConnectionTimeoutDuration = completedResponse.metrics.totalDuration;
    NSLog(@"Idle Timeout Excludes Initial Connection: %.3fs", completedResponse.metrics.totalDuration);

    // No Idle Timeout
    [TNLGlobalConfiguration sharedInstance].idleTimeoutMode = TNLGlobalConfigurationIdleTimeoutModeDisabled;
    completedResponse = nil;
    operation = [TNLRequestOperation operationWithRequest:request configuration:config completion:^(TNLRequestOperation *op, TNLResponse *response) {
        completedResponse = response;
    }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertNil(completedResponse.operationError);
    XCTAssertGreaterThan(completedResponse.metrics.totalDuration, withoutConnectionTimeoutDuration);
    NSLog(@"Idle Timeout Disabled: %.3fs", completedResponse.metrics.totalDuration);

    [TNLGlobalConfiguration sharedInstance].idleTimeoutMode = TNLGlobalConfigurationIdleTimeoutModeDefault;
    [TNLPseudoURLProtocol unregisterEndpoint:URL];
}

- (void)testOrderOfCallbacks
{
    NSDictionary *args = @{@"method":@"get"};
    TNLMutableHTTPRequest *request = [self httpBinRequest:args];
    request.HTTPMethodValue = TNLHTTPMethodGET;
    TNLMutableRequestConfiguration *config = self.config;
    TestTNLRequestDelegate *delegate = [[TestTNLRequestDelegate alloc] init];
    [self registerRequest:request args:args];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request responseClass:[TestJSONResponse class] configuration:config delegate:delegate];
    op.context = delegate;

    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    [self unregisterRequest:request];

    NSArray<NSString *> *expectedCallbacks = @[
                                               NSStringFromSelector(@selector(tnl_requestOperation:didReceiveURLResponse:)),
                                               NSStringFromSelector(@selector(tnl_requestOperation:didCompleteAttemptWithResponse:disposition:)),
                                               NSStringFromSelector(@selector(tnl_requestOperation:didCompleteWithResponse:))
                                               ];
    NSArray<NSString *> *observedCallbacks = delegate.observedCallbacks;
    XCTAssertEqualObjects(expectedCallbacks, observedCallbacks);
}

@end

@implementation TestJSONResponse

- (void)prepare
{
    [super prepare];

    NSError *error = nil;
    if (!_operationError) {
        NSData *data = nil;
        if (_info.data) {
            data = _info.data;
        } else if (_info.temporarySavedFile) {
            _responseBodyWasInFile = YES;
            NSString *newFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
            if ([_info.temporarySavedFile moveToPath:newFilePath error:&error]) {
                data = [NSData dataWithContentsOfFile:newFilePath options:0 error:&error];
                [[NSFileManager defaultManager] removeItemAtPath:newFilePath error:NULL];
            }
        }

        @try {
            _result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        } @catch (NSException *e) {
            _jsonParseError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINTR userInfo:nil];
        }
    }
}

@end

@implementation TestTNLRequestDelegate
{
    dispatch_queue_t _slowQueue;
    dispatch_queue_t _fastQueue;
    NSMutableArray<NSString *> *_cmds;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _fastQueue = dispatch_queue_create("test.queue.fast", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_fastQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        _slowQueue = dispatch_queue_create("test.queue.slow", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_slowQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
        _cmds = [[NSMutableArray alloc] init];
    }
    return self;
}

- (dispatch_queue_t)tnl_delegateQueueForRequestOperation:(TNLRequestOperation *)op
{
    return _slowQueue;
}

- (dispatch_queue_t)tnl_completionQueueForRequestOperation:(TNLRequestOperation *)op
{
    return _fastQueue;
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didReceiveURLResponse:(NSURLResponse *)response
{
    SEL cmd = _cmd;
    sleep(2);
    dispatch_sync(_fastQueue, ^{
        [self trackSelector:cmd];
    });
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteAttemptWithResponse:(TNLResponse *)response disposition:(TNLAttemptCompleteDisposition)disposition
{
    SEL cmd = _cmd;
    sleep(1);
    dispatch_sync(_fastQueue, ^{
        [self trackSelector:cmd];
    });
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteWithResponse:(TNLResponse *)response
{
    [self trackSelector:_cmd];
}

- (void)trackSelector:(SEL)cmd
{
    NSString *cmdString = NSStringFromSelector(cmd);
    [_cmds addObject:cmdString];
}

- (NSArray<NSString *> *)observedCallbacks
{
    __block NSArray<NSString *> *cmds;
    __block NSUInteger dummy;
    dispatch_sync(_slowQueue, ^{
        dummy = (NSUInteger)self;
    });
    dummy++;
    dispatch_sync(_fastQueue, ^{
        cmds = [self->_cmds copy];
    });
    return cmds;
}

@end

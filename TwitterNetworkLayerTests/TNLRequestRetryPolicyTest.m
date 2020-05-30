//
//  TNLRequestRetryPolicyTest.m
//  TwitterNetworkLayerTests
//
//  Created on 8/24/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLXContentEncoding.h"

@import TwitterNetworkLayer;
@import XCTest;

#define kDELAY_TIME_INTERVAL (0.2)

@interface BrokenContentEncoder : NSObject <TNLContentEncoder>
@end

@interface TestRetryPolicy : NSObject <TNLConfiguringRetryPolicyProvider>
@property (nonatomic) NSTimeInterval retryDelay;
@property (nonatomic) NSUInteger maxAttempts;
@end

@interface TimerOperation : NSOperation
- (instancetype)initWithTimeout:(NSTimeInterval)timeout;
@end

@interface TNLRequestRetryPolicyTest : XCTestCase <TNLRequestDelegate>
@end

@implementation TNLRequestRetryPolicyTest
{
    TNLResponse *_response;
    NSTimeInterval _dependencyDuration;
    NSTimeInterval _dependencyDelay;
    NSTimeInterval _retryDelay;
    dispatch_block_t _onNextRetry;
}

- (void)tearDown
{
    [super tearDown];
    _response = nil;
    _dependencyDuration = 0;
    _dependencyDelay = 0;
    _retryDelay = 0;
    _onNextRetry = nil;
}

- (void)testRetryPolicy
{
    for (_retryDelay = 0.0; _retryDelay < (kDELAY_TIME_INTERVAL * 1.5); _retryDelay += kDELAY_TIME_INTERVAL) {
        for (_dependencyDuration = 0.0; _dependencyDuration < (kDELAY_TIME_INTERVAL * 1.5); _dependencyDuration += kDELAY_TIME_INTERVAL) {
            for (_dependencyDelay = 0.0; _dependencyDelay < (kDELAY_TIME_INTERVAL * 1.5); _dependencyDelay += kDELAY_TIME_INTERVAL) {
                NSString *cmdStr = NSStringFromSelector(_cmd);
                NSLog(@"%@: retry-delay=%fs, dependency-duration=%fs, dependency-delay=%fs", cmdStr, _retryDelay, _dependencyDuration, _dependencyDelay);
                const CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                [self _runRetryPolicyTest];
                const NSTimeInterval duration = CFAbsoluteTimeGetCurrent() - start;
                NSLog(@"%@: run=%fs", cmdStr, duration);
                _response = nil;
            }
        }
    }
}

- (void)_runRetryPolicyTest
{
    TestRetryPolicy *retryPolicy = [[TestRetryPolicy alloc] initWithConfiguration:[TNLRequestRetryPolicyConfiguration standardConfiguration]];
    retryPolicy.retryDelay = _retryDelay;
    NSURL *URL = [NSURL URLWithString:@"https://fake.domain.com/post/results"];
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.contentEncoder = [[BrokenContentEncoder alloc] init];
    config.retryPolicyProvider = retryPolicy;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;

    NSHTTPURLResponse *URLResponse = [[NSHTTPURLResponse alloc] initWithURL:URL
                                                                 statusCode:200
                                                                HTTPVersion:@"1.1"
                                                               headerFields:nil];
    NSData *URLResponseBody = [@"{\"success\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    [TNLPseudoURLProtocol registerURLResponse:URLResponse
                                         body:URLResponseBody
                                 withEndpoint:URL];
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    NSDictionary *results = @{
                              @"player1" : @{
                                      @"name" : @"Montoya",
                                      @"score" : @5,
                                      },
                              @"player2" : @{
                                      @"name" : @"Roberts",
                                      @"score" : @6,
                                      }
                              };
    NSData *requestBody = [NSJSONSerialization dataWithJSONObject:results
                                                          options:NSJSONWritingPrettyPrinted
                                                            error:NULL];
    TNLMutableHTTPRequest *request = [TNLMutableHTTPRequest POSTRequestWithURL:URL
                                                              HTTPHeaderFields:nil
                                                                      HTTPBody:requestBody];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                          configuration:config
                                                               delegate:self];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertNotNil(_response);
    XCTAssertEqual((int)_response.info.statusCode, 200);
    XCTAssertNil(_response.operationError);
    XCTAssertEqual((int)_response.metrics.attemptCount, 2);
    XCTAssertGreaterThan(_response.metrics.totalDuration, MAX(_retryDelay, _dependencyDuration + _dependencyDelay));
#if 0 // disable this since the CI machines can have really slow performance -- feel free to enable when running locally
    XCTAssertLessThan(_response.metrics.totalDuration, MAX(_retryDelay, _dependencyDuration + _dependencyDelay) + kDELAY_TIME_INTERVAL);
#endif

    do {
        TNLAttemptMetrics *firstAttemptMetrics = _response.metrics.attemptMetrics.firstObject;
        XCTAssertNotNil(firstAttemptMetrics);
        XCTAssertNotNil(firstAttemptMetrics.operationError);
        XCTAssertEqualObjects(firstAttemptMetrics.operationError.domain, TNLErrorDomain);
        XCTAssertEqual(firstAttemptMetrics.operationError.code, TNLErrorCodeRequestOperationRequestContentEncodingFailed);
    } while (0);

    do {
        NSData *requestBodyBase64 = [requestBody base64EncodedDataWithOptions:(NSDataBase64Encoding64CharacterLineLength |
                                                                               NSDataBase64EncodingEndLineWithCarriageReturn |
                                                                               NSDataBase64EncodingEndLineWithLineFeed)];
        TNLAttemptMetrics *lastAttemptMetrics = _response.metrics.attemptMetrics.lastObject;
        XCTAssertNotNil(lastAttemptMetrics);
        XCTAssertNil(lastAttemptMetrics.operationError);
        XCTAssertEqualObjects([lastAttemptMetrics.URLRequest valueForHTTPHeaderField:@"Content-Encoding"], @"base64");
        XCTAssertEqualObjects(lastAttemptMetrics.URLRequest.HTTPBody, requestBodyBase64);
    } while (0);
}

#pragma mark Test specific scenarios

- (void)testSuccessfulRequestDoesNotRetry
{
    NSURL *URL = [NSURL URLWithString:@"https://fake.domain.com/"];
    TNLMutableHTTPRequest *request = [TNLMutableHTTPRequest GETRequestWithURL:URL HTTPHeaderFields:nil];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [TNLPseudoURLProtocol registerURLResponse:response body:nil withEndpoint:URL];
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    TNLRequestRetryPolicyConfiguration *retryConfig = [[TNLRequestRetryPolicyConfiguration alloc] initWithAllMethodsRetriableAndRetriableStatusCodes:@[@200] URLErrorCodes:nil POSIXErrorCodes:nil];
    TestRetryPolicy *retryPolicy = [[TestRetryPolicy alloc] initWithConfiguration:retryConfig];

    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.retryPolicyProvider = retryPolicy;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;

    TNLRequestOperation *operation = [TNLRequestOperation operationWithRequest:request configuration:config delegate:self];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(operation.attemptCount, 1);
    XCTAssertEqual(operation.retryCount, 0);
    XCTAssertEqual(operation.response.info.statusCode, 200);
}

- (void)testRetryWhenSubsequentRequestSucceeds
{
    NSURL *URL = [NSURL URLWithString:@"https://fake.domain.com/"];
    TNLMutableHTTPRequest *request = [TNLMutableHTTPRequest GETRequestWithURL:URL HTTPHeaderFields:nil];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:503 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    NSHTTPURLResponse *successResponse = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [TNLPseudoURLProtocol registerURLResponse:response body:nil withEndpoint:URL];
    _onNextRetry = ^{
        [TNLPseudoURLProtocol registerURLResponse:successResponse body:nil withEndpoint:URL];
    };
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    TestRetryPolicy *retryPolicy = [[TestRetryPolicy alloc] initWithConfiguration:[TNLRequestRetryPolicyConfiguration standardConfiguration]];

    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.retryPolicyProvider = retryPolicy;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;

    TNLRequestOperation *operation = [TNLRequestOperation operationWithRequest:request configuration:config delegate:self];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(operation.attemptCount, 2);
    XCTAssertEqual(operation.retryCount, 1);
    XCTAssertEqual(operation.response.info.statusCode, 200);
}

- (void)testOperationTimeoutCancelsRetry
{
    // The actual timeout here does not matter, as long as it is enough for
    // the initial attempt to complete. If the retryDelay is longer than the
    // operationTimeout the retry should not be attempted.
    static const NSTimeInterval operationTimeout = 30.0;
    static const NSTimeInterval retryDelay = 40.0;

    NSURL *URL = [NSURL URLWithString:@"https://fake.domain.com/"];
    TNLMutableHTTPRequest *request = [TNLMutableHTTPRequest GETRequestWithURL:URL HTTPHeaderFields:nil];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:503 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [TNLPseudoURLProtocol registerURLResponse:response body:nil withEndpoint:URL];
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    TestRetryPolicy *retryPolicy = [[TestRetryPolicy alloc] initWithConfiguration:[TNLRequestRetryPolicyConfiguration standardConfiguration]];
    retryPolicy.retryDelay = retryDelay;

    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.retryPolicyProvider = retryPolicy;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;
    config.operationTimeout = operationTimeout;
    config.attemptTimeout = operationTimeout;
    config.idleTimeout = operationTimeout;

    TNLRequestOperation *operation = [TNLRequestOperation operationWithRequest:request configuration:config delegate:self];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(operation.attemptCount, 1);
    XCTAssertEqual(operation.retryCount, 0);
    XCTAssertEqual(operation.response.info.statusCode, 503);
}

- (void)testRetryWithNoOperationTimeout
{
    // The operation should retry if the `operationTimeout` is unlimited (less than 0.1 per docs).
    // There used to be a bug where `operationTimeout` less than 0.1 would NEVER retry.
    // This test prevents regression from fixing this particular bug.

    NSURL *URL = [NSURL URLWithString:@"https://fake.domain.com/"];
    TNLMutableHTTPRequest *request = [TNLMutableHTTPRequest GETRequestWithURL:URL HTTPHeaderFields:nil];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:503 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [TNLPseudoURLProtocol registerURLResponse:response body:nil withEndpoint:URL];
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    TestRetryPolicy *retryPolicy = [[TestRetryPolicy alloc] initWithConfiguration:[TNLRequestRetryPolicyConfiguration standardConfiguration]];
    retryPolicy.maxAttempts = 1;

    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.retryPolicyProvider = retryPolicy;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;
    config.operationTimeout = -1;

    TNLRequestOperation *operation = [TNLRequestOperation operationWithRequest:request configuration:config delegate:self];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];

    XCTAssertEqual(operation.attemptCount, 2);
    XCTAssertEqual(operation.retryCount, 1);
    XCTAssertEqual(operation.response.info.statusCode, 503);
}

#pragma mark - TNLRequestDelegate

- (void)tnl_requestOperation:(TNLRequestOperation *)op
  willStartRetryFromResponse:(TNLResponse *)responseBeforeRetry
              policyProvider:(id<TNLRequestRetryPolicyProvider>)policyProvider
                  afterDelay:(NSTimeInterval)delay
{
    if (_onNextRetry) {
        _onNextRetry();
        _onNextRetry = nil;
    }

    if (_dependencyDelay < 0.1 && _dependencyDuration < 0.1) {
        return;
    }

    NSOperation *timeoutOp = [[TimerOperation alloc] initWithTimeout:_dependencyDuration];
    [op addDependency:timeoutOp];
    NSOperation *delayOp = [[TimerOperation alloc] initWithTimeout:_dependencyDelay];
    [timeoutOp addDependency:delayOp];
    NSOperationQueue *q = [NSOperationQueue currentQueue] ?: [NSOperationQueue mainQueue];
    [q addOperation:timeoutOp];
    [q addOperation:delayOp];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TNLResponse *)response
{
    _response = response;
}

@end

@implementation BrokenContentEncoder

- (NSString *)tnl_contentEncodingType
{
    return @"gzip";
}

- (nullable NSData *)tnl_encodeHTTPBody:(NSData *)bodyData
                                  error:(out NSError * __nullable * __nullable)error
{
    if (error) {
        *error = [NSError errorWithDomain:@"broken.encoder"
                                     code:-2
                                 userInfo:nil];
    }
    return nil;
}

@end

@implementation TestRetryPolicy
{
    TNLRequestRetryPolicyConfiguration *_config;
}

- (instancetype)initWithConfiguration:(nullable TNLRequestRetryPolicyConfiguration *)config
{
    if (self = [super init]) {
        _config = [config copy];
    }
    return self;
}

- (nullable TNLRequestRetryPolicyConfiguration *)configuration
{
    return _config;
}

- (BOOL)tnl_shouldRetryRequestOperation:(TNLRequestOperation *)op
                           withResponse:(TNLResponse *)response
{
    if (_maxAttempts && op.attemptCount > _maxAttempts) {
        return NO;
    }

    if ([response.operationError.domain isEqualToString:TNLErrorDomain] && response.operationError.code == TNLErrorCodeRequestOperationRequestContentEncodingFailed) {
        if (response.metrics.attemptCount > 3) {
            return NO;
        }
        return YES;
    }

    return [_config requestCanBeRetriedForResponse:response];
}

- (NSTimeInterval)tnl_delayBeforeRetryForRequestOperation:(TNLRequestOperation *)op
                                             withResponse:(TNLResponse *)response
{
    return _retryDelay;
}

- (nullable TNLRequestConfiguration *)tnl_configurationOfRetryForRequestOperation:(TNLRequestOperation *)op
                                                                     withResponse:(TNLResponse *)response
                                                               priorConfiguration:(TNLRequestConfiguration *)priorConfig
{
    if (![response.operationError.domain isEqualToString:TNLErrorDomain]) {
        return nil;
    }

    if (response.operationError.code != TNLErrorCodeRequestOperationRequestContentEncodingFailed) {
        return nil;
    }

    TNLMutableRequestConfiguration *config = [priorConfig mutableCopy];
    if ([priorConfig.contentEncoder.tnl_contentEncodingType isEqualToString:@"base64"]) {
        config.contentEncoder = nil;
    } else {
        config.contentEncoder = [TNLXContentEncoding Base64ContentEncoder];
    }

    return config;
}

- (nullable NSString *)tnl_retryPolicyIdentifier
{
    return @"test.tnl.retry.policy.1";
}

@end

@implementation TimerOperation
{
    NSTimeInterval _timeout;
    BOOL _finished;
    BOOL _executing;
}

- (instancetype)initWithTimeout:(NSTimeInterval)timeout
{
    if (self = [super init]) {
        _timeout = timeout;
    }
    return self;
}

- (void)start
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        _finished = YES;
        [self didChangeValueForKey:@"isFinished"];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    _executing = YES;
    [self didChangeValueForKey:@"isExecuting"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_timeout * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self completeOperation];
    });
}

- (BOOL)isExecuting
{
    return _executing;
}

- (BOOL)isFinished
{
    return _finished;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (void)completeOperation
{
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    _executing = NO;
    _finished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end


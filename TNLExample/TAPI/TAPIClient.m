//
//  TAPIRequestManager.m
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <CommonCrypto/CommonHMAC.h>

#include <stdatomic.h>

#import "TAPIClient.h"
#import "TAPIError.h"
#import "TNL_Project.h"

static NSData *HMAC_SHA1(NSString *data, NSString *key);
static NSData *HMAC_SHA1(NSString *data, NSString *key)
{
    unsigned char buf[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, [key UTF8String], key.length, [data UTF8String], data.length, buf);
    return [NSData dataWithBytes:buf length:CC_SHA1_DIGEST_LENGTH];
}

@interface TAPIClient () <TNLRequestDelegate>
@end

@interface TAPIOperationContext : NSObject
@property (nonatomic) NSOperation *loginOperation;
@property (nonatomic, copy, readonly) NSString *oauthNonce;
@property (nonatomic, copy) TAPIRequestCompletionBlock completionBlock;
@end

@interface TAPILoginOperation : TNLSafeOperation
@property (nonatomic, weak) TAPIClient *client;
- (BOOL)didSucceed;
@end

@implementation TAPIOperationContext

- (instancetype)init
{
    self = [super init];
    if (self) {
        _oauthNonce = [[NSUUID UUID] UUIDString];
    }
    return self;
}

@end

@implementation TAPIClient
{
    dispatch_queue_t _loginQueue;
    NSMutableArray<NSOperation *> *_loginOperations;
    NSString *_oauthAccessToken;
    NSString *_oauthAccessSecret;
}

+ (instancetype)sharedInstance
{
    static TAPIClient *sManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sManager = [[TAPIClient alloc] init];
    });
    return sManager;
}

- (instancetype)init
{
    if (self = [super init]) {
        _loginAccessBlock = nil;
        _loginQueue = dispatch_queue_create("login.queue", DISPATCH_QUEUE_SERIAL);
        _loginOperations = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSOperation *)triggerLogin:(TAPILoginCompletionBlock)loginBlock
{
    TAPILoginOperation *op = [[TAPILoginOperation alloc] init];
    op.client = self;
    if (loginBlock) {
        __unsafe_unretained TAPILoginOperation *opRef = op;
        op.completionBlock = ^{
            TAPIClient *client = opRef.client;
            if (client) {
                dispatch_sync(client->_loginQueue, ^{
                    [client->_loginOperations removeObject:opRef];
                });
            }
            const BOOL didSucceed = opRef.didSucceed;
            dispatch_async(dispatch_get_main_queue(), ^{
                loginBlock(didSucceed);
            });
        };
    }

    dispatch_sync(_loginQueue, ^{
        for (NSOperation *otherOp in self->_loginOperations) {
            [op addDependency:otherOp];
        }
        [self->_loginOperations addObject:op];
    });
    [[NSOperationQueue mainQueue] tnl_safeAddOperation:op];
    return op;
}

- (TNLRequestOperation *)_tapi_startRequest:(TAPIRequest *)request
                                   delegate:(id<TNLRequestDelegate>)delegate
                                 completion:(TAPIRequestCompletionBlock)completion
{
    Class requestClass = [request class];
    TNLMutableRequestConfiguration *config = [[requestClass configuration] mutableCopy];
    config.retryPolicyProvider = [requestClass retryPolicyProvider];

    TAPIOperationContext *context = [[TAPIOperationContext alloc] init];
    context.loginOperation = [self triggerLogin:NULL];
    context.completionBlock = completion;

    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                          responseClass:[requestClass responseClass] ?: [TAPIResponse class]
                                                          configuration:config
                                                               delegate:delegate];
    if (context.loginOperation) {
        [op addDependency:context.loginOperation];
    }
    op.context = context;

    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    return op;
}

- (TNLRequestOperation *)startRequest:(TAPIRequest *)request
                           completion:(TAPIRequestCompletionBlock)completion
{
    return [self _tapi_startRequest:request
                           delegate:self
                         completion:completion];
}

- (TNLRequestOperation *)startRequest:(TAPIRequest *)request
                             delegate:(id<TNLRequestDelegate>)delegate
{
    return [self _tapi_startRequest:request
                           delegate:delegate
                         completion:nil];
}

#pragma mark TNLRequestHydrater

- (dispatch_queue_t)tnl_delegateQueueForRequestOperation:(TNLRequestOperation *)op
{
    return _loginQueue;
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
              hydrateRequest:(TAPIRequest *)request
                  completion:(TNLRequestHydrateCompletionBlock)complete
{
    complete([TNLHTTPRequest HTTPRequestWithRequest:request], nil);
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
         authorizeURLRequest:(NSURLRequest *)URLRequest
                  completion:(TNLAuthorizeCompletionBlock)completion
{
    // This method is externally exposed so it could be called on any thread.
    // Ensure we are on the correct queue.
    if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) != dispatch_queue_get_label(_loginQueue)) {
        dispatch_async(_loginQueue, ^{
            [self tnl_requestOperation:op
                   authorizeURLRequest:URLRequest
                            completion:completion];
        });
        return;
    }

    NSString *consumerKey = self.oauthConsumerKey;
    NSString *consumerSecret = self.oauthConsumerSecret;
    if (!consumerKey || !consumerSecret) {
        completion(nil, [NSError errorWithDomain:TAPIOperationErrorDomain
                                            code:TAPIOperationErrorCodeMissingConsumerCredentials
                                        userInfo:nil]);
        return;
    }

    NSString *oauthSecret = _oauthAccessSecret;
    NSString *oauthToken = _oauthAccessToken;
    if (!oauthSecret || !oauthToken) {
        completion(nil, [NSError errorWithDomain:TAPIOperationErrorDomain
                                            code:TAPIOperationErrorCodeMissingAccessCredentials
                                        userInfo:nil]);
        return;
    }

    TAPIRequest *request = (id)op.originalRequest;
    TAPIOperationContext *context = op.context;
    NSString *method = [TNLRequest HTTPMethodForRequest:URLRequest];
    NSString *baseURLString = [request baseURLString];
    TNLMutableParameterCollection *params = [[request parameters] mutableCopy] ?:  [[TNLMutableParameterCollection alloc] init];

    NSMutableDictionary *oauthParams = [[NSMutableDictionary alloc] init];
    oauthParams[@"oauth_nonce"] = context.oauthNonce;
    oauthParams[@"oauth_timestamp"] = [NSString stringWithFormat:@"%qd", (long long)[[NSDate date] timeIntervalSince1970]];
    oauthParams[@"oauth_signature_method"] = @"HMAC-SHA1";
    oauthParams[@"oauth_version"] = @"1.0";
    oauthParams[@"oauth_consumer_key"] = self.oauthConsumerKey;
    oauthParams[@"oauth_token"] = oauthToken;
    [params addParametersDirectlyFromDictionary:oauthParams combineRepeatingKeys:NO];

    NSString *oauthString = [NSString stringWithFormat:@"%@&%@&%@", method, TNLURLEncodeString(baseURLString), TNLURLEncodeString([params stableURLEncodedStringValue])];
    NSString *signingKey = [NSString stringWithFormat:@"%@&%@", self.oauthConsumerSecret, oauthSecret];
    NSData *signatureBytes = HMAC_SHA1(oauthString, signingKey);
    NSString *signatureBase64 = [signatureBytes base64EncodedStringWithOptions:0];
    oauthParams[@"oauth_signature"] = signatureBase64;

    NSMutableArray *authHeaderItems = [NSMutableArray array];
    for (NSString *key in oauthParams) {
        NSString *value = oauthParams[key];
        [authHeaderItems addObject:[NSString stringWithFormat:@"%@=\"%@\"", key, TNLURLEncodeString(value)]];
    }

    NSString *authString = [NSString stringWithFormat:@"OAuth %@", [authHeaderItems componentsJoinedByString:@", "]];
    completion(authString, nil);
}

#pragma mark TNLRequestDelegate

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TAPIResponse *)response
{
    TNLAssert([op.originalRequest isKindOfClass:[TAPIRequest class]]);
    TNLAssert([response isKindOfClass:[TAPIResponse class]]);
    TAPIOperationContext *context = op.context;
    TAPIRequestCompletionBlock completion = context.completionBlock;
    if (completion) {
        assert([NSThread isMainThread]);
        completion(response);
    }
}

#pragma mark Internal

- (void)_tapi_login:(TAPILoginCompletionBlock)completion
{
    dispatch_async(_loginQueue, ^{
        if (self->_oauthAccessSecret && self->_oauthAccessToken) {
            completion(YES);
            return;
        }

        TAPILoginAccessBlock loginBlock = self.loginAccessBlock;
        if (!loginBlock) {
            completion(NO);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            loginBlock(^(NSString *token, NSString *secret) {
                dispatch_async(self->_loginQueue, ^{
                    self->_oauthAccessToken = [token copy];
                    self->_oauthAccessSecret = [secret copy];
                    completion((token != nil && secret != nil));
                });
            });
        });
    });
}

@end

@implementation TAPILoginOperation
{
    volatile atomic_bool _isFinished;
    volatile atomic_bool _isExecuting;
    volatile atomic_bool _didStart;
    volatile atomic_bool _didSucceed;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        atomic_init(&_isFinished, false);
        atomic_init(&_isExecuting, false);
        atomic_init(&_didStart, false);
        atomic_init(&_didSucceed, false);
    }
    return self;
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    return atomic_load(&_isExecuting);
}

- (BOOL)isFinished
{
    return atomic_load(&_isFinished);
}

- (BOOL)didSucceed
{
    return atomic_load(&_didSucceed);
}

- (void)start
{
    tnl_defer(^{
        atomic_store(&(self->_didStart), true);
    });

    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&_isExecuting, true);
    [self didChangeValueForKey:@"isExecuting"];

    TAPIClient *client = self.client;
    if (!client) {
        [self complete];
        return;
    }

    [client _tapi_login:^(BOOL loginSucceeded) {
        atomic_store(&self->_didSucceed, loginSucceeded);
        [self complete];
    }];
}

- (void)complete
{
    if (false == atomic_load(&self->_didStart)) {
        // Completed synchronously, don't want to mess up "isAsynchronous" behavior
        dispatch_async(dispatch_get_main_queue(), ^{
            [self complete];
        });
        return;
    }

    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    atomic_store(&self->_isExecuting, false);
    atomic_store(&self->_isFinished, true);
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

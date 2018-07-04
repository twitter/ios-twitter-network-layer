//
//  NSURLCache+TNLAdditionsTest.m
//  TwitterNetworkLayer
//
//  Created on 10/28/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLCache+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLHTTPRequest.h"
#import "TNLNetwork.h"
#import "TNLPseudoURLProtocol.h"
#import "TNLRequestDelegate.h"
#import "TNLRequestOperation.h"
#import "TNLRequestOperationQueue.h"
#import "TNLResponse_Project.h"

@import XCTest;

@interface NSURLCache_TNLAdditionsTest : XCTestCase
@property (atomic) NSUInteger spinUps;
@end

@implementation NSURLCache_TNLAdditionsTest

- (void)testNSURLImpotentCache
{
    NSURLCache *cache = [NSURLCache tnl_impotentURLCache];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.dummy.com/path?something=else"]];
    NSURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Header1" : @"Value1" }];
    NSCachedURLResponse *cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response data:[@"Random Data" dataUsingEncoding:NSUTF8StringEncoding] userInfo:nil storagePolicy:NSURLCacheStorageAllowed];

    XCTAssertEqual(0UL, cache.currentMemoryUsage);
    XCTAssertEqual(0UL, cache.currentDiskUsage);
    XCTAssertNil([cache cachedResponseForRequest:request]);

    [cache storeCachedResponse:cachedResponse forRequest:request];

    XCTAssertEqual(0UL, cache.currentMemoryUsage);
    XCTAssertEqual(0UL, cache.currentDiskUsage);
    XCTAssertNil([cache cachedResponseForRequest:request]);
}

+ (TNLResponse *)GETResponseWithURL:(NSURL *)URL config:(TNLRequestConfiguration *)config
{
    __block TNLResponse *response = nil;
    TNLHTTPRequest *request = [TNLHTTPRequest GETRequestWithURL:URL HTTPHeaderFields:nil];
    TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                          configuration:config
                                                             completion:^(TNLRequestOperation *operation, TNLResponse *opResponse) {
        response = opResponse;
    }];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    return response;
}

- (void)testCacheHitDetection
{
    NSURL *URL = [NSURL URLWithString:@"http://cache.dummy.com/cacheable"];
    NSData *body = [URL.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *headers = @{
                              @"content-length" : [@(body.length) description],
                              @"cache-control" : @"max-age=10000",
                              @"date" : TNLHTTPDateToString([NSDate date], TNLHTTPDateFormatAuto),
                              };
    NSHTTPURLResponse *URLResponse = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [TNLPseudoURLProtocol registerURLResponse:URLResponse body:body withEndpoint:URL];
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSStringFromSelector(_cmd)];
    NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:1024*1024*10 diskCapacity:1024*1024*10 diskPath:path];
    [cache removeAllCachedResponses];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.5]]; // give cache time to purge
    tnl_defer(^{
        [cache removeAllCachedResponses];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.5]]; // give cache time to purge
    });

    TNLResponse *response = nil;
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.cachePolicy = NSURLRequestReturnCacheDataElseLoad;
    config.URLCache = cache;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;

    response = [[self class] GETResponseWithURL:URL config:config];
    XCTAssertEqualObjects(response.info.data, body);
    XCTAssertEqual(response.info.source, TNLResponseSourceNetworkRequest);

    response = [[self class] GETResponseWithURL:URL config:config];
    XCTAssertEqualObjects(response.info.data, body);
    XCTAssertEqual(response.info.source, TNLResponseSourceLocalCache);

    config.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    response = [[self class] GETResponseWithURL:URL config:config];
    XCTAssertEqualObjects(response.info.data, body);
    XCTAssertEqual(response.info.source, TNLResponseSourceNetworkRequest);
    [cache removeAllCachedResponses];

    config.cachePolicy = NSURLRequestReturnCacheDataDontLoad;
    response = [[self class] GETResponseWithURL:URL config:config];
    XCTAssertNil(response.info.data);
    XCTAssertNotNil(response.operationError);
    XCTAssertEqual(response.info.source, TNLResponseSourceNetworkRequest);
}

- (void)testSessionCoalescing
{
    NSURL *URL = [NSURL URLWithString:@"http://cache.dummy.com/cacheable"];
    NSData *body = [URL.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *headers = @{
                              @"content-length" : [@(body.length) description],
                              @"cache-control" : @"max-age=10000",
                              @"date" : TNLHTTPDateToString([NSDate date], TNLHTTPDateFormatAuto),
                              };
    NSHTTPURLResponse *URLResponse = [[NSHTTPURLResponse alloc] initWithURL:URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [TNLPseudoURLProtocol registerURLResponse:URLResponse body:body withEndpoint:URL];
    tnl_defer(^{
        [TNLPseudoURLProtocol unregisterEndpoint:URL];
    });

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_didSpinUpSession:)
                                                 name:TNLNetworkDidSpinUpSessionNotification
                                               object:nil];

    NSURLCache *cache = nil;
    TNLResponse *response = nil;
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
    config.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.protocolOptions = TNLRequestProtocolOptionPseudo;

    // warm the NSURLSessions
    response = [[self class] GETResponseWithURL:URL config:config];
    const NSUInteger originalSpinUpCount = self.spinUps;

    // 1) shared cache

    cache = [NSURLCache sharedURLCache];
    config.URLCache = cache;
    tnl_defer(^{
        [cache removeAllCachedResponses];
    });
    response = [[self class] GETResponseWithURL:URL config:config];


    // 2) proxy shared cache

    cache = [NSURLCache tnl_sharedURLCacheProxy];
    config.URLCache = cache;
    tnl_defer(^{
        [cache removeAllCachedResponses];
    });
    response = [[self class] GETResponseWithURL:URL config:config];

    // 3) impotent cache

    cache = [NSURLCache tnl_impotentURLCache];
    config.URLCache = cache;
    tnl_defer(^{
        [cache removeAllCachedResponses];
    });
    response = [[self class] GETResponseWithURL:URL config:config];

    // 4) nil cache

    cache = nil;
    config.URLCache = cache;
    tnl_defer(^{
        [cache removeAllCachedResponses];
    });
    response = [[self class] GETResponseWithURL:URL config:config];

    if (@available(macOS 10.10, iOS 8, tvOS 9, watchOS 2, *)) {
        // modern OSes with TNL will use demuxing to avoid spinning up multiple sessions
        XCTAssertEqual(originalSpinUpCount, self.spinUps);
    } else {
        // legacy OSes with TNL cannot demuxing and will have a session per cache instance
        XCTAssertLessThan(originalSpinUpCount, self.spinUps);
    }
}

- (void)_didSpinUpSession:(NSNotification *)note
{
    self.spinUps++;
}

@end

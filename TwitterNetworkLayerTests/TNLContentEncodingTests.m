//
//  TNLContentEncodingTests.m
//  TwitterNetworkLayer
//
//  Created on 11/21/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import <XCTest/XCTest.h>

#import "TNLXContentEncoding.h"

@interface TNLContentEncodingTests : XCTestCase
@end

static NSData *sJSONData = nil;
static NSData *sBase64Data = nil;
static NSURL *sJSONURL = nil;
static NSURL *sBase64URL = nil;
static TNLMutableRequestConfiguration *sConfig = nil;
static id<TNLContentEncoder> sBase64Encoder = nil;
static id<TNLContentDecoder> sBase64Decoder = nil;

@implementation TNLContentEncodingTests

+ (void)setUp
{
    NSBundle *bundle = [NSBundle bundleForClass:self];
    NSString *jsonDataPath = [bundle pathForResource:@"BingResults" ofType:@"json"];
    NSString *base64DataPath = [bundle pathForResource:@"BingResults.json" ofType:@"base64"];
    sJSONData = [NSData dataWithContentsOfFile:jsonDataPath];
    sBase64Data = [NSData dataWithContentsOfFile:base64DataPath];
    sBase64URL = [NSURL URLWithString:@"https://www.dummy.com/base64"];
    sJSONURL = [NSURL URLWithString:@"https://www.dummy.com/json"];
    NSHTTPURLResponse *base64Response = [[NSHTTPURLResponse alloc] initWithURL:sBase64URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Content-Encoding" : @"base64", @"Content-Type" : TNLHTTPContentTypeJSON, @"Content-Length" : @(sBase64Data.length).stringValue }];
    NSHTTPURLResponse *jsonResponse = [[NSHTTPURLResponse alloc] initWithURL:sJSONURL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Content-Type" : TNLHTTPContentTypeJSON, @"Content-Length" : @(sJSONData.length).stringValue }];
    TNLPseudoURLResponseConfig *pseudoConfig = [[TNLPseudoURLResponseConfig alloc] init];
    pseudoConfig.bps = 500000;
    pseudoConfig.latency = 5;

    [TNLPseudoURLProtocol registerURLResponse:base64Response body:sBase64Data config:pseudoConfig withEndpoint:sBase64URL];
    [TNLPseudoURLProtocol registerURLResponse:jsonResponse body:sJSONData config:pseudoConfig withEndpoint:sJSONURL];

    sConfig = [TNLMutableRequestConfiguration defaultConfiguration];
    sConfig.attemptTimeout = NSTimeIntervalSince1970;
    sConfig.idleTimeout = NSTimeIntervalSince1970;
    sConfig.operationTimeout = NSTimeIntervalSince1970;
    sConfig.protocolOptions = TNLRequestProtocolOptionPseudo;

    sBase64Encoder = [TNLXContentEncoding Base64ContentEncoder];
    sBase64Decoder = [TNLXContentEncoding Base64ContentDecoder];
}

+ (void)tearDown
{
    sJSONData = nil;
    sBase64Data = nil;
    sJSONURL = nil;
    sBase64URL = nil;
    sConfig = nil;
    sBase64Decoder = nil;
    sBase64Encoder = nil;
    [TNLPseudoURLProtocol unregisterAllEndpoints];
}

- (void)tearDown
{
    sConfig.additionalContentDecoders = nil;
    sConfig.contentEncoder = nil;
    [super tearDown];
}

- (void)testBase64Encoding
{
    TNLRequestOperation *op = nil;
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    request.HTTPMethod = @"POST";
    NSArray<NSString *> *knownCodecs;
    if ([NSURLSessionConfiguration tnl_URLSessionSupportsDecodingBrotliContentEncoding]) {
        knownCodecs = @[ @"br", @"deflate", @"gzip" ];
    } else {
        knownCodecs = @[ @"deflate", @"gzip" ];
    }

    // unencoded JSON in
    // unencoded JSON out

    request.URL = sJSONURL;
    request.HTTPBody = sJSONData;
    op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqual(op.response.info.statusCode, 200);
    XCTAssertNil(op.response.info.allHTTPHeaderFields[@"Content-Encoding"]);
    XCTAssertNotNil(op.response.info.data);
    XCTAssertEqualObjects(op.response.info.data, sJSONData);
    XCTAssertEqualObjects(op.hydratedURLRequest.HTTPBody, sJSONData);


    // unencoded JSON in
    // encoded JSON out

    request.URL = sBase64URL;
    request.HTTPBody = sJSONData;
    op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqual(op.response.info.statusCode, 200);
    XCTAssertEqualObjects(op.response.info.allHTTPHeaderFields[@"Content-Encoding"], @"base64");
    XCTAssertNotNil(op.response.info.data);
    XCTAssertEqualObjects(op.response.info.data, sBase64Data);
    XCTAssertEqualObjects(op.hydratedURLRequest.HTTPBody, sJSONData);

    // unencoded JSON in
    // decoded JSON out

    sConfig.additionalContentDecoders = @[ sBase64Decoder ];
    request.URL = sBase64URL;
    request.HTTPBody = sJSONData;
    op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqual(op.response.info.statusCode, 200);
    XCTAssertEqualObjects(op.response.info.allHTTPHeaderFields[@"Content-Encoding"], @"base64");
    NSArray<NSString *> *acceptEncodings = [@[ @"base64" ] arrayByAddingObjectsFromArray:knownCodecs];
    XCTAssertEqualObjects([op.hydratedURLRequest valueForHTTPHeaderField:@"Accept-Encoding"], [acceptEncodings componentsJoinedByString:@", "]);
    XCTAssertNotNil(op.response.info.data);
    XCTAssertEqualObjects(op.response.info.data, sJSONData);
    XCTAssertEqualObjects(op.hydratedURLRequest.HTTPBody, sJSONData);

    // encoded JSON in
    // decoded JSON out (Accept-Encoding overridden)

    sConfig.contentEncoder = sBase64Encoder;
    request.URL = sBase64URL;
    request.HTTPBody = sJSONData;
    [request setValue:@"base64;q=0.8, base32;q=0.4, gzip;q=1.0" forHTTPHeaderField:@"Accept-Encoding"];
    op = [TNLRequestOperation operationWithRequest:request configuration:sConfig delegate:nil];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    [op waitUntilFinishedWithoutBlockingRunLoop];
    XCTAssertEqual(op.response.info.statusCode, 200);
    XCTAssertEqualObjects(op.response.info.allHTTPHeaderFields[@"Content-Encoding"], @"base64");
    XCTAssertEqualObjects([op.hydratedURLRequest valueForHTTPHeaderField:@"Accept-Encoding"], @"base64;q=0.8, base32;q=0.4, gzip;q=1.0");
    XCTAssertNotNil(op.response.info.data);
    XCTAssertEqualObjects(op.response.info.data, sJSONData);
    NSData *decoded = [[NSData alloc] initWithBase64EncodedData:op.hydratedURLRequest.HTTPBody options:NSDataBase64DecodingIgnoreUnknownCharacters];
    XCTAssertEqualObjects(decoded ?: op.hydratedURLRequest.HTTPBody, sJSONData);
}

@end

//
//  TNLRequestTests.m
//  TwitterNetworkLayer
//
//  Created on 10/28/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLError.h"
#import "TNLHTTPRequest.h"
#import "TNLRequestConfiguration.h"

@import XCTest;

@interface TNLRequestTests : XCTestCase

@end

@implementation TNLRequestTests

- (void)testConcreteRequestConstructors
{
    TNLHTTPRequest *request;

    NSURL *url = [NSURL URLWithString:@"http://www.dummy.com/path?something=else"];
    TNLHTTPMethod method = TNLHTTPMethodPOST;
    NSDictionary *fields = @{ @"Header1" : @"Value1", @"Header2" : @"Value2" };
    NSData *body = [@"Body String" dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *mURLRequest = [NSMutableURLRequest requestWithURL:url];
    mURLRequest.HTTPMethod = @"POST";
    mURLRequest.HTTPBody = body;
    mURLRequest.allHTTPHeaderFields = fields;

    request = [[TNLHTTPRequest alloc] initWithURL:url HTTPMethodValue:method HTTPHeaderFields:fields HTTPBody:body HTTPBodyStream:nil HTTPBodyFilePath:nil];
    XCTAssertEqualObjects(request.URL, url);
    XCTAssertEqual(request.HTTPMethodValue, method);
    XCTAssertEqualObjects(request.allHTTPHeaderFields, fields);
    XCTAssertEqualObjects(request.HTTPBody, body);
    XCTAssertEqualObjects(@"Value1", [request valueForHTTPHeaderField:@"Header1"]);

    request = [[TNLHTTPRequest alloc] initWithURLRequest:mURLRequest];
    XCTAssertEqualObjects(request.URL, url);
    XCTAssertEqual(request.HTTPMethodValue, method);
    XCTAssertEqualObjects(request.allHTTPHeaderFields, fields);
    XCTAssertEqualObjects(request.HTTPBody, body);
    XCTAssertEqualObjects(@"Value1", [request valueForHTTPHeaderField:@"Header1"]);
}

- (void)testConcreteRequestMutability
{
    TNLHTTPRequest *request;
    TNLMutableHTTPRequest *mRequest;

    NSURL *url = [NSURL URLWithString:@"http://www.dummy.com/path?something=else"];
    TNLHTTPMethod method = TNLHTTPMethodPOST;
    NSDictionary *fields = @{ @"Header1" : @"Value1", @"Header2" : @"Value2" };
    NSData *body = [@"Body String" dataUsingEncoding:NSUTF8StringEncoding];

    mRequest = [[TNLMutableHTTPRequest alloc] initWithURL:nil];
    mRequest.URL = url;
    mRequest.HTTPMethodValue = TNLHTTPMethodPOST;
    mRequest.allHTTPHeaderFields = fields;
    mRequest.HTTPBody = body;

    request = [[TNLHTTPRequest alloc] initWithURL:url HTTPMethodValue:method HTTPHeaderFields:fields HTTPBody:body HTTPBodyStream:nil HTTPBodyFilePath:nil];

    XCTAssertEqualObjects(mRequest, request);
    XCTAssertEqualObjects([mRequest copy], mRequest);
    XCTAssertEqualObjects([mRequest mutableCopy], mRequest);
    XCTAssertEqualObjects([request copy], request);
    XCTAssertEqualObjects([request mutableCopy], request);

    XCTAssertTrue([mRequest isKindOfClass:[TNLMutableHTTPRequest class]]);
    XCTAssertTrue([[mRequest mutableCopy] isKindOfClass:[TNLMutableHTTPRequest class]]);
    XCTAssertTrue([[request mutableCopy] isKindOfClass:[TNLMutableHTTPRequest class]]);

    XCTAssertFalse([request isKindOfClass:[TNLMutableHTTPRequest class]]);
    XCTAssertFalse([[request copy] isKindOfClass:[TNLMutableHTTPRequest class]]);
    XCTAssertFalse([[mRequest copy] isKindOfClass:[TNLMutableHTTPRequest class]]);

    XCTAssertEqualObjects(@"Value1", [mRequest valueForHTTPHeaderField:@"header1"]);
    [mRequest setValue:@"ValueX" forHTTPHeaderField:@"HEADER1"];
    XCTAssertEqualObjects(@"ValueX", [mRequest valueForHTTPHeaderField:@"header1"]);
    XCTAssertNotEqualObjects(mRequest, request);
}

- (void)testRequestValidate
{
    TNLMutableHTTPRequest *mRequest;
    NSMutableURLRequest *mURLRequest;
    NSError *error;
    NSData *data = [@"Body" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:@"http://www.dummy.com/path?something=else"];
    TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];

    mURLRequest = [NSMutableURLRequest requestWithURL:url];
    mURLRequest.HTTPBody = data;
    mURLRequest.HTTPMethod = @"POST";
    mURLRequest.allHTTPHeaderFields = @{ @"Header1" : @"Value1", @"Header2" : @"Value2" };
    mRequest = [[TNLMutableHTTPRequest alloc] initWithURLRequest:mURLRequest];
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));

    XCTAssertTrue(TNLRequestValidate(mURLRequest, config, &error));
    XCTAssertNil(error);
    if (error) {
        NSLog(@"%@", error);
    }
    XCTAssertTrue(TNLRequestValidate(mRequest, config, &error));
    XCTAssertNil(error);
    if (error) {
        NSLog(@"%@", error);
    }

    // IDYN-357, POSTs and PUTs support the body being optional
    mURLRequest.HTTPBody = nil;
    mRequest.HTTPBody = nil;
    XCTAssertTrue(TNLRequestValidate(mURLRequest, config, &error));
    XCTAssertNil(error);
    error = nil;
    XCTAssertTrue(TNLRequestValidate(mRequest, config, &error));
    XCTAssertNil(error);
    error = nil;

    mURLRequest.HTTPBody = data;
    mRequest.HTTPBody = data;
    XCTAssertTrue(TNLRequestValidate(mURLRequest, config, NULL /*errorOut*/));
    XCTAssertTrue(TNLRequestValidate(mRequest, config, NULL /*errorOut*/));

    mURLRequest.URL = nil;
    mRequest.URL = nil;
    XCTAssertFalse(TNLRequestValidate(mURLRequest, config, &error));
    XCTAssertEqualObjects(error.domain, TNLErrorDomain);
    error = nil;
    XCTAssertFalse(TNLRequestValidate(mRequest, config, &error));
    XCTAssertEqualObjects(error.domain, TNLErrorDomain);
    error = nil;

    mURLRequest.URL = url;
    mRequest.URL = url;
    XCTAssertTrue(TNLRequestValidate(mURLRequest, config, NULL /*errorOut*/));
    XCTAssertTrue(TNLRequestValidate(mRequest, config, NULL /*errorOut*/));

    mURLRequest.HTTPMethod = @"GET";
    mRequest.HTTPMethodValue = TNLHTTPMethodGET;
    XCTAssertTrue(TNLRequestValidate(mURLRequest, config, NULL /*errorOut*/));
    XCTAssertTrue(TNLRequestValidate(mRequest, config, NULL /*errorOut*/));
}

- (void)testRequestConversion
{
    TNLMutableHTTPRequest *mRequest;
    NSMutableURLRequest *mURLRequest;
    NSError *error;
    NSData *data = [@"Body" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:@"http://www.dummy.com/path?something=else"];

    mURLRequest = [NSMutableURLRequest requestWithURL:url];
    mURLRequest.HTTPBody = data;
    mURLRequest.HTTPMethod = @"POST";
    mURLRequest.allHTTPHeaderFields = @{ @"Header1" : @"Value1", @"Header2" : @"Value2" };
    mRequest = [[TNLMutableHTTPRequest alloc] initWithURLRequest:mURLRequest];
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));

    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));

    mRequest.HTTPBody = [@"Body2" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));
    mURLRequest.HTTPBody = mRequest.HTTPBody;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));

    mRequest.HTTPBody = nil;
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));
    mURLRequest.HTTPBody = nil;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));

    mRequest.HTTPBody = data;
    mURLRequest.HTTPBody = data;

    mRequest.HTTPMethodValue = TNLHTTPMethodGET;
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));
    mURLRequest.HTTPMethod = @"GET";
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));

    mRequest.HTTPBody = nil;
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));
    mURLRequest.HTTPBody = nil;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));

    mRequest.URL = [NSURL URLWithString:@"http://www.dummy.com/path"];
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));
    mURLRequest.URL = mRequest.URL;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, TNLRequestToNSURLRequest(mRequest, nil, &error), NO /*quickBodyCheck*/));
}

- (void)testMethodConversion
{
    NSMutableURLRequest *mURLRequest = [[NSMutableURLRequest alloc] init];
    TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] initWithURLRequest:mURLRequest];

    NSArray *enums = @[ @(TNLHTTPMethodOPTIONS),
                        @(TNLHTTPMethodGET),
                        @(TNLHTTPMethodHEAD),
                        @(TNLHTTPMethodPOST),
                        @(TNLHTTPMethodPUT),
                        @(TNLHTTPMethodDELETE),
                        @(TNLHTTPMethodTRACE),
                        @(TNLHTTPMethodCONNECT) ];
    NSArray *strings = @[ @"OPTIONS",
                          @"GET",
                          @"HEAD",
                          @"POST",
                          @"PUT",
                          @"DELETE",
                          @"TRACE",
                          @"CONNECT" ];

    XCTAssertEqual(enums.count, strings.count);

    for (NSUInteger i = 0; i < enums.count; i++) {
        mURLRequest.HTTPMethod = [strings[i] mutableCopy]; // the mutation will ensure the string is different than the global @"TERM" reference
        mRequest.HTTPMethodValue = [enums[i] integerValue];

        XCTAssertEqualObjects(strings[i], TNLRequestGetHTTPMethod(mURLRequest));
        XCTAssertEqualObjects(strings[i], TNLRequestGetHTTPMethod(mRequest));
        XCTAssertEqual([enums[i] integerValue], TNLRequestGetHTTPMethodValue(mURLRequest));
        XCTAssertEqual([enums[i] integerValue], TNLRequestGetHTTPMethodValue(mRequest));
    }
}

- (void)testRequestEquivalence
{
    TNLMutableHTTPRequest *mRequest;
    NSMutableURLRequest *mURLRequest;
    NSData *data = [@"Body" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:@"http://www.dummy.com/path?something=else"];

    mURLRequest = [NSMutableURLRequest requestWithURL:url];
    mURLRequest.HTTPBody = data;
    mURLRequest.HTTPMethod = @"POST";
    mURLRequest.allHTTPHeaderFields = @{ @"Header1" : @"Value1", @"Header2" : @"Value2" };

    mRequest = [[TNLMutableHTTPRequest alloc] initWithURLRequest:mURLRequest];
    mRequest.allHTTPHeaderFields = @{ @"header1" : @"Value1", @"HEADER2" : @"Value2" };

    XCTAssertNotEqualObjects(mURLRequest, mRequest);
    XCTAssertEqualObjects(mURLRequest, [mURLRequest copy]);
    XCTAssertEqualObjects(mRequest, [mRequest copy]);
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    XCTAssertTrue(TNLRequestEqualToRequest([mURLRequest copy], mRequest, NO /*quickBodyCheck*/));
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, [mRequest copy], NO /*quickBodyCheck*/));
    XCTAssertTrue(TNLRequestEqualToRequest([mURLRequest copy], [mRequest copy], NO /*quickBodyCheck*/));

    mURLRequest.HTTPBody = [@"Body2" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    mRequest.HTTPBody = mURLRequest.HTTPBody;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    mURLRequest.HTTPMethod = @"GET";
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    mRequest.HTTPMethodValue = TNLHTTPMethodGET;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    mRequest.HTTPBody = nil;
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    mURLRequest.HTTPBody = nil;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    mRequest.URL = [NSURL URLWithString:@"http://www.dummy.com/path"];
    XCTAssertFalse(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
    mURLRequest.URL = mRequest.URL;
    XCTAssertTrue(TNLRequestEqualToRequest(mURLRequest, mRequest, NO /*quickBodyCheck*/));
}

@end

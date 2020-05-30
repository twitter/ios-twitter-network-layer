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
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:mRequest]);

    XCTAssertTrue([TNLRequest validateRequest:mURLRequest againstConfiguration:config error:&error]);
    XCTAssertNil(error);
    if (error) {
        NSLog(@"%@", error);
    }
    XCTAssertTrue([TNLRequest validateRequest:mRequest againstConfiguration:config error:&error]);
    XCTAssertNil(error);
    if (error) {
        NSLog(@"%@", error);
    }

    // IDYN-357, POSTs and PUTs support the body being optional
    mURLRequest.HTTPBody = nil;
    mRequest.HTTPBody = nil;
    XCTAssertTrue([TNLRequest validateRequest:mURLRequest againstConfiguration:config error:&error]);
    XCTAssertNil(error);
    error = nil;
    XCTAssertTrue([TNLRequest validateRequest:mRequest againstConfiguration:config error:&error]);
    XCTAssertNil(error);
    error = nil;

    mURLRequest.HTTPBody = data;
    mRequest.HTTPBody = data;
    XCTAssertTrue([TNLRequest validateRequest:mURLRequest againstConfiguration:config error:NULL]);
    XCTAssertTrue([TNLRequest validateRequest:mRequest againstConfiguration:config error:NULL]);

    mURLRequest.URL = nil;
    mRequest.URL = nil;
    XCTAssertFalse([TNLRequest validateRequest:mURLRequest againstConfiguration:config error:&error]);
    XCTAssertEqualObjects(error.domain, TNLErrorDomain);
    error = nil;
    XCTAssertFalse([TNLRequest validateRequest:mRequest againstConfiguration:config error:&error]);
    XCTAssertEqualObjects(error.domain, TNLErrorDomain);
    error = nil;

    mURLRequest.URL = url;
    mRequest.URL = url;
    XCTAssertTrue([TNLRequest validateRequest:mURLRequest againstConfiguration:config error:NULL]);
    XCTAssertTrue([TNLRequest validateRequest:mRequest againstConfiguration:config error:NULL]);

    mURLRequest.HTTPMethod = @"GET";
    mRequest.HTTPMethodValue = TNLHTTPMethodGET;
    XCTAssertTrue([TNLRequest validateRequest:mURLRequest againstConfiguration:config error:NULL]);
    XCTAssertTrue([TNLRequest validateRequest:mRequest againstConfiguration:config error:NULL]);
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
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:mRequest]);

    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);

    mRequest.HTTPBody = [@"Body2" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);
    mURLRequest.HTTPBody = mRequest.HTTPBody;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);

    mRequest.HTTPBody = nil;
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);
    mURLRequest.HTTPBody = nil;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);

    mRequest.HTTPBody = data;
    mURLRequest.HTTPBody = data;

    mRequest.HTTPMethodValue = TNLHTTPMethodGET;
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);
    mURLRequest.HTTPMethod = @"GET";
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);

    mRequest.HTTPBody = nil;
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);
    mURLRequest.HTTPBody = nil;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);

    mRequest.URL = [NSURL URLWithString:@"http://www.dummy.com/path"];
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);
    mURLRequest.URL = mRequest.URL;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:[TNLRequest URLRequestForRequest:mRequest error:&error]]);
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

        XCTAssertEqualObjects(strings[i], [TNLRequest HTTPMethodForRequest:mURLRequest]);
        XCTAssertEqualObjects(strings[i], [TNLRequest HTTPMethodForRequest:mRequest]);
        XCTAssertEqual([enums[i] integerValue], [TNLRequest HTTPMethodValueForRequest:mURLRequest]);
        XCTAssertEqual([enums[i] integerValue], [TNLRequest HTTPMethodValueForRequest:mURLRequest]);
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
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    XCTAssertTrue([TNLRequest isRequest:[mURLRequest copy] equalTo:mRequest]);
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:[mRequest copy]]);
    XCTAssertTrue([TNLRequest isRequest:[mURLRequest copy] equalTo:[mRequest copy]]);

    mURLRequest.HTTPBody = [@"Body2" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    mRequest.HTTPBody = mURLRequest.HTTPBody;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    mURLRequest.HTTPMethod = @"GET";
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    mRequest.HTTPMethodValue = TNLHTTPMethodGET;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    mRequest.HTTPBody = nil;
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    mURLRequest.HTTPBody = nil;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    mRequest.URL = [NSURL URLWithString:@"http://www.dummy.com/path"];
    XCTAssertFalse([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
    mURLRequest.URL = mRequest.URL;
    XCTAssertTrue([TNLRequest isRequest:mURLRequest equalTo:mRequest]);
}

@end

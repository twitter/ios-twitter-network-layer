//
//  NSURLSessionConfiguration+TNLAdditionsTest.m
//  TwitterNetworkLayer
//
//  Created on 10/28/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "NSURLSessionConfiguration+TNLAdditions.h"

@import XCTest;

@interface NSURLSessionConfiguration_TNLAdditionsTest : XCTestCase

@end

@implementation NSURLSessionConfiguration_TNLAdditionsTest

- (void)testNSURLSessionConfigurationCementing
{
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];

    XCTAssertEqualObjects(config.URLCache, config.URLCache);
    XCTAssertEqualObjects(config.URLCredentialStorage, config.URLCredentialStorage);
    XCTAssertEqualObjects(config.HTTPCookieStorage, config.HTTPCookieStorage);

    XCTAssertEqualObjects(config.URLCache, config.URLCache);
    XCTAssertEqualObjects(config.URLCredentialStorage, config.URLCredentialStorage);
    XCTAssertEqualObjects(config.HTTPCookieStorage, config.HTTPCookieStorage);
}

@end

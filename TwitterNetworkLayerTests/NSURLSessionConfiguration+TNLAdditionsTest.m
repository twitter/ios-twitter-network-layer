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

    XCTAssertEqual([config respondsToSelector:@selector(setSharedContainerIdentifier:)], [NSURLSessionConfiguration tnl_supportsSharedContainerIdentifier]);

    if (![config respondsToSelector:@selector(setSharedContainerIdentifier:)]) {

        // iOS 7

        XCTAssertNotEqualObjects(config.URLCache, config.URLCache);
        XCTAssertNotEqualObjects(config.URLCredentialStorage, config.URLCredentialStorage);
        XCTAssertNotEqualObjects(config.HTTPCookieStorage, config.HTTPCookieStorage);
    } else {

        // iOS 8+

        XCTAssertEqualObjects(config.URLCache, config.URLCache);
        XCTAssertEqualObjects(config.URLCredentialStorage, config.URLCredentialStorage);
        XCTAssertEqualObjects(config.HTTPCookieStorage, config.HTTPCookieStorage);
    }

    [NSURLSessionConfiguration tnl_cementConfiguration:config];

    XCTAssertEqualObjects(config.URLCache, config.URLCache);
    XCTAssertEqualObjects(config.URLCredentialStorage, config.URLCredentialStorage);
    XCTAssertEqualObjects(config.HTTPCookieStorage, config.HTTPCookieStorage);
}

@end

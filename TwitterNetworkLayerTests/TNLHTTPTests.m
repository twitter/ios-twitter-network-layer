//
//  TNLHTTPTests.m
//  TwitterNetworkLayer
//
//  Created on 10/30/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import "TNLHTTP.h"

@import XCTest;

@interface TNLHTTPTests : XCTestCase

@end

@implementation TNLHTTPTests

- (void)testHTTPDates
{
    NSString *RFC822DateString = @"Sun, 06 Nov 1994 08:49:37 GMT";
    NSString *RFC850DateString = @"Sunday, 06-Nov-94 08:49:37 GMT";
    NSString *asctimeDateString = @"Sun Nov  6 08:49:37 1994";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:784111777LL];
    TNLHTTPDateFormat format = TNLHTTPDateFormatUnknown;

    // Parse valid

    XCTAssertEqualObjects(TNLHTTPDateFromString(RFC822DateString, &format), date);
    XCTAssertEqual(format, TNLHTTPDateFormatRFC822);
    XCTAssertEqualObjects(TNLHTTPDateFromString(RFC850DateString, &format), date);
    XCTAssertEqual(format, TNLHTTPDateFormatRFC850);
    XCTAssertEqualObjects(TNLHTTPDateFromString(asctimeDateString, &format), date);
    XCTAssertEqual(format, TNLHTTPDateFormatANSIC);

    // Parse invalid

    format = TNLHTTPDateFormatANSIC;
    XCTAssertNil(TNLHTTPDateFromString(@"", &format));
    XCTAssertEqual(format, TNLHTTPDateFormatUnknown);
    format = TNLHTTPDateFormatANSIC;
    XCTAssertNil(TNLHTTPDateFromString(@"Blah, Blah, Blah", &format));
    XCTAssertEqual(format, TNLHTTPDateFormatUnknown);
    format = TNLHTTPDateFormatANSIC;
    XCTAssertNil(TNLHTTPDateFromString(nil, &format));
    XCTAssertEqual(format, TNLHTTPDateFormatUnknown);

    // Write valid

    XCTAssertEqualObjects(TNLHTTPDateToString(date, TNLHTTPDateFormatANSIC), asctimeDateString);
    XCTAssertEqualObjects(TNLHTTPDateToString(date, TNLHTTPDateFormatRFC822), RFC822DateString);
    XCTAssertEqualObjects(TNLHTTPDateToString(date, TNLHTTPDateFormatRFC850), RFC850DateString);
    XCTAssertEqualObjects(TNLHTTPDateToString(date, TNLHTTPDateFormatAuto), RFC822DateString);
    XCTAssertEqualObjects(TNLHTTPDateToString(date, (TNLHTTPDateFormat)-1), RFC822DateString);

    // Write invalid

    XCTAssertNil(TNLHTTPDateToString(nil, TNLHTTPDateFormatAuto));
}

@end

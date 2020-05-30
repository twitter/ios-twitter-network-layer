//
//  TNLTemporaryFileTest.m
//  TwitterNetworkLayer
//
//  Created on 10/28/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLTemporaryFile_Project.h"

@import XCTest;

@interface TNLTemporaryFileTest : XCTestCase

@end

@implementation TNLTemporaryFileTest

- (void)testInnerMethods
{
    NSString *destination = [NSTemporaryDirectory() stringByAppendingString:@"temp_file.tmp"];
    TNLTemporaryFile *tmpFile = [[TNLTemporaryFile alloc] init];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;

    [fm removeItemAtPath:destination error:NULL];

    XCTAssertNotNil(tmpFile.path);
    XCTAssertFalse([fm fileExistsAtPath:tmpFile.path]);

    XCTAssertFalse([tmpFile appendData:[@"Data" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertNotNil(error);
    error = nil;

    XCTAssertTrue([tmpFile close:&error]); // closing a closed tmp file is a no-op, not an error
    XCTAssertNil(error);
    error = nil;

    XCTAssertFalse([tmpFile moveToPath:destination error:&error]);
    XCTAssertNotNil(error);
    error = nil;

    XCTAssertFalse(tmpFile.isOpen);

    XCTAssertTrue([tmpFile open:&error]);
    XCTAssertNil(error);
    error = nil;

    XCTAssertTrue(tmpFile.isOpen);

    XCTAssertTrue([tmpFile open:&error]); // redundant open is a no-op, not an error
    XCTAssertNil(error);
    error = nil;

    XCTAssertTrue(tmpFile.isOpen);

    XCTAssertTrue([tmpFile appendData:[@"Append data\n" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertNil(error);
    error = nil;

    XCTAssertFalse([tmpFile moveToPath:destination error:&error]);
    XCTAssertNotNil(error);
    error = nil;

    XCTAssertTrue([tmpFile close:&error]);
    XCTAssertNil(error);
    error = nil;

    XCTAssertFalse(tmpFile.isOpen);

    XCTAssertFalse([tmpFile appendData:[@"Data" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertNotNil(error);
    error = nil;

    XCTAssertTrue([tmpFile close:&error]);
    XCTAssertNil(error);
    error = nil;

    XCTAssertTrue([tmpFile moveToPath:destination error:&error]);
    XCTAssertNil(error);
    error = nil;

    XCTAssertTrue([fm fileExistsAtPath:destination]);

    XCTAssertFalse([tmpFile moveToPath:destination error:&error]);
    XCTAssertNotNil(error);
    error = nil;

    [fm removeItemAtPath:destination error:NULL];
}

- (void)testAutoDelete
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmpFilePath = nil;

    @autoreleasepool {
        TNLTemporaryFile *tmpFile = [[TNLTemporaryFile alloc] init];
        [tmpFile open:NULL];
        [tmpFile appendData:[@"Data" dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
        [tmpFile close:NULL];
        tmpFilePath = tmpFile.path;
        XCTAssertTrue([fm fileExistsAtPath:tmpFilePath]);
    }
    XCTAssertFalse([fm fileExistsAtPath:tmpFilePath]);

    @autoreleasepool {
        TNLTemporaryFile *tmpFile = [[TNLTemporaryFile alloc] init];
        [tmpFile open:NULL];
        [tmpFile appendData:[@"Data" dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
        tmpFilePath = tmpFile.path;
        XCTAssertTrue([fm fileExistsAtPath:tmpFilePath]);
    }
    XCTAssertFalse([fm fileExistsAtPath:tmpFilePath]);

    @autoreleasepool {
        TNLTemporaryFile *tmpFile = [[TNLTemporaryFile alloc] init];
        [tmpFile open:NULL];
        tmpFilePath = tmpFile.path;
        XCTAssertTrue([fm fileExistsAtPath:tmpFilePath]);
    }
    XCTAssertFalse([fm fileExistsAtPath:tmpFilePath]);
}

- (void)testCreateWithExistingFile
{
    TNLTemporaryFile *tmpFile;
    NSString *destination = [NSTemporaryDirectory() stringByAppendingString:@"temp_file2.tmp"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    [fm removeItemAtPath:destination error:NULL];

    tmpFile = [TNLTemporaryFile temporaryFileWithExistingFilePath:destination error:&error];
    XCTAssertNil(tmpFile);
    XCTAssertNotNil(error);
    error = nil;

    [@"Data" writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([fm fileExistsAtPath:destination]);
    tmpFile = [TNLTemporaryFile temporaryFileWithExistingFilePath:destination error:&error];
    XCTAssertNotNil(tmpFile);
    XCTAssertNil(error);
    error = nil;
    XCTAssertFalse([fm fileExistsAtPath:destination]);
}

@end

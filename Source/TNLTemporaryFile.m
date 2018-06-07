//
//  TNLTemporaryFile.m
//  TwitterNetworkLayer
//
//  Created on 7/18/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLTemporaryFile_Project.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TNLTemporaryFile
{
    BOOL _exists;
    FILE *_file;
}

+ (nullable instancetype)temporaryFileWithExistingFilePath:(NSString *)path
                                                     error:(out NSError **)error
{
    TNLTemporaryFile *file = [[TNLTemporaryFile alloc] init];
    if (![file consumeExistingFile:path error:error]) {
        file = nil;
    }
    return file;
}

- (instancetype)init
{
    if (self = [super init]) {
        _path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    }
    return self;
}

- (void)dealloc
{
    [self close:NULL];
    if (_exists) {
        [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    }
}

- (BOOL)isOpen
{
    return !!_file;
}

- (BOOL)consumeExistingFile:(NSString *)path error:(out NSError **)error
{
    NSError *theError = nil;
    if (_exists) {
        theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                       code:EEXIST
                                   userInfo:@{ @"existing" : _path, @"source" : path ?: [NSNull null] }];
    } else {
        if ([[NSFileManager defaultManager] moveItemAtPath:path toPath:_path error:&theError]) {
            _exists = YES;
        } else {
            TNLAssert(theError != nil);
        }
    }

    if (error) {
        *error = theError;
    }

    return !theError;
}

- (BOOL)close:(out NSError **)error
{
    NSError *theError = nil;

    if (_file) {
        if (0 == fclose(_file)) {
            _file = NULL;
        } else {
            theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                           code:errno
                                       userInfo:nil];
        }
    }

    if (error) {
        *error = theError;
    }

    return !theError;
}

- (BOOL)open:(out NSError **)error
{
    NSError *theError = nil;

    if (!_file) {
        _file = fopen(_path.UTF8String, "a");
        if (!_file) {
            theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                           code:errno
                                       userInfo:nil];
        } else {
            _exists = YES;
        }
    }

    if (error) {
        *error = theError;
    }

    return !theError;
}

- (BOOL)appendData:(NSData *)data error:(out NSError **)error
{
    NSError *theError = nil;

    if (_file) {
        NSUInteger length = data.length;
        NSUInteger written = fwrite(data.bytes, 1, length, _file);
        if (length != written) {
            theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                           code:ferror(_file)
                                       userInfo:nil];
        }
    } else {
        theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                       code:ENOENT
                                   userInfo:nil];
    }

    if (error) {
        *error = theError;
    }

    return !theError;
}

- (BOOL)moveToPath:(NSString *)path error:(out NSError **)error
{
    NSError *theError = nil;

    if (!_file) {
        if ([[NSFileManager defaultManager] moveItemAtPath:_path toPath:path error:&theError]) {
            _exists = NO;
        }
    } else {
        theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                       code:EBUSY
                                   userInfo:@{ @"message" : @"the file is still open for writing, please close the file before moving it." }];
    }

    if (error) {
        *error = theError;
    }

    return !theError;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ : %p, open=%@, exists=%@, path='%@'>", NSStringFromClass([self class]), self, self.isOpen ? @"YES" : @"NO", _exists ? @"YES" : @"NO", _path];
}

@end

@implementation TNLExpiredTemporaryFile

- (instancetype)initWithFilePath:(nullable NSString *)path
{
    if (self = [super init]) {
        _path = [path copy];
    }
    return self;
}

- (instancetype)init
{
    return [self initWithFilePath:nil];
}

- (BOOL)moveToPath:(NSString *)path error:(out NSError **)error
{
    NSError *theError = nil;
    if (_path) {
        theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                       code:ENOENT
                                   userInfo:@{ @"message" : @"the temporary file has expired and is no longer available to move.", @"path" : _path }];
    } else {
        theError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                       code:EINVAL
                                   userInfo:@{ @"message" : @"there is no temporary file to move." }];
    }

    if (error) {
        *error = theError;
    }

    return !theError;
}

@end

id<TNLTemporaryFile> __nullable TNLTemporaryFileConstructedFromExistingFile(NSString *filePath,
                                                                            NSError * __nullable * __nullable errorOut)
{
    return [TNLTemporaryFile temporaryFileWithExistingFilePath:filePath
                                                         error:errorOut];
}

NS_ASSUME_NONNULL_END

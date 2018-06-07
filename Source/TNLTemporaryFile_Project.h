//
//  TNLTemporaryFile_Project.h
//  TwitterNetworkLayer
//
//  Created on 7/18/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "TNLTemporaryFile.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

@interface TNLTemporaryFile : NSObject <TNLTemporaryFile>

- (instancetype)init;
+ (nullable instancetype)temporaryFileWithExistingFilePath:(NSString *)path
                                                     error:(out NSError * __nullable * __nullable)error;

@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, getter = isOpen) BOOL open;

- (BOOL)consumeExistingFile:(NSString *)path
                      error:(out NSError * __nullable * __nullable)error;
- (BOOL)close:(out NSError * __nullable * __nullable)error;
- (BOOL)open:(out NSError * __nullable * __nullable)error;
- (BOOL)appendData:(NSData *)data
             error:(out NSError * __nullable * __nullable)error;

@end

@interface TNLExpiredTemporaryFile : NSObject <TNLTemporaryFile>

- (instancetype)initWithFilePath:(nullable NSString *)path;
- (instancetype)init;

@property (nonatomic, readonly, nullable) NSString *path;

@end

NS_ASSUME_NONNULL_END

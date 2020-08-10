//
//  TNLTemporaryFile_Project.h
//  TwitterNetworkLayer
//
//  Created on 7/18/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLTemporaryFile.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

TNL_OBJC_FINAL
@interface TNLTemporaryFile : NSObject <TNLTemporaryFile>

+ (nullable instancetype)temporaryFileWithExistingFilePath:(NSString *)path
                                                     error:(out NSError * __nullable * __nullable)error;

@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, getter = isOpen) BOOL open;

- (BOOL)consumeExistingFile:(NSString *)path
                      error:(out NSError * __nullable * __nullable)error TNL_OBJC_DIRECT;
- (BOOL)close:(out NSError * __nullable * __nullable)error;
- (BOOL)open:(out NSError * __nullable * __nullable)error;
- (BOOL)appendData:(NSData *)data error:(out NSError * __nullable * __nullable)error;

@end

TNL_OBJC_FINAL
@interface TNLExpiredTemporaryFile : NSObject <TNLTemporaryFile>

- (instancetype)initWithFilePath:(nullable NSString *)path TNL_OBJC_DIRECT;

@property (nonatomic, readonly, nullable) NSString *path;

@end

NS_ASSUME_NONNULL_END

//
//  TNLCLIExecutionContext.h
//  TNLCLI
//
//  Created on 9/11/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

@import Foundation;

@class TNLResponse;

NS_ASSUME_NONNULL_BEGIN

@interface TNLCLIExecutionContext : NSObject

#pragma mark Context Error

@property (nonatomic, readonly, nullable) NSError *contextError;

#pragma mark Execution Info

@property (nonatomic, readonly, copy, nullable) NSString *executableName;
@property (nonatomic, readonly, copy, nullable) NSString *executableDirectory;
@property (nonatomic, readonly, copy, nullable) NSString *currentDirectory;

#pragma mark Global Config

@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *globalConfigurations;

#pragma mark Request Info

@property (nonatomic, readonly, copy, nullable) NSString *requestConfigurationFilePath;
@property (nonatomic, readonly, copy, nullable) NSString *requestHeadersFilePath;
@property (nonatomic, readonly, copy, nullable) NSString *requestBodyFilePath;
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *requestHeaders;
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *requestConfigurations;
@property (nonatomic, readonly, copy, nullable) NSString *requestMethodValueString;
@property (nonatomic, readonly, copy, nullable) NSString *requestURLString;

#pragma mark Response Info

@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *responseBodyOutputModes; // @"file", @"print", @"file,print"
@property (nonatomic, readonly, copy, nullable) NSString *responseBodyTargetFilePath;

@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *responseHeadersOutputModes; // @"file", @"print", @"file,print"
@property (nonatomic, readonly, copy, nullable) NSString *responseHeadersTargetFilePath;

@property (nonatomic, readonly, copy, nullable) NSString *certificateChainDumpDirectory;

#pragma mark Other Info

@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic, readonly) BOOL printVersion; // --version

#pragma mark Init

- (instancetype)initWithArgC:(int)argc argV:(const char * __nonnull * __nonnull)argv;
- (instancetype)initWithArgs:(nullable NSArray<NSString *> *)args NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

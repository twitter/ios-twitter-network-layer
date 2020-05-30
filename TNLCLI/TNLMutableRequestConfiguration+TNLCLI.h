//
//  TNLMutableRequestConfiguration+TNLCLI.h
//  tnlcli
//
//  Created on 9/17/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLRequestConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@interface TNLMutableRequestConfiguration (TNLCLI)

+ (nullable instancetype)tnlcli_configurationWithFile:(NSString *)filePath error:(NSError * __nullable * __nullable)errorOut;
+ (instancetype)tnlcli_configurationWithDictionary:(nullable NSDictionary<NSString *, NSString *> *)d;

- (BOOL)tnlcli_applySettingWithName:(NSString *)name value:(NSString *)value;

@end

NS_ASSUME_NONNULL_END

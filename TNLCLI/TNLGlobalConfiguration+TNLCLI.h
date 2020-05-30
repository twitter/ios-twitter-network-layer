//
//  TNLGlobalConfiguration+TNLCLI.h
//  tnlcli
//
//  Created on 9/17/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLGlobalConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@interface TNLGlobalConfiguration (TNLCLI)

- (BOOL)tnlcli_applySettingWithName:(NSString *)name value:(NSString *)value;

@end

NS_ASSUME_NONNULL_END

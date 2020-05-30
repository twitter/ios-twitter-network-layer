//
//  TNLCLIExecution.h
//  tnlcli
//
//  Created on 9/12/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLCLIExecutionContext.h"

NS_ASSUME_NONNULL_BEGIN

@interface TNLCLIExecution : NSObject

@property (nonatomic, readonly) TNLCLIExecutionContext *context;

- (instancetype)initWithContext:(TNLCLIExecutionContext *)context;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable NSError *)execute;

@end

NS_ASSUME_NONNULL_END

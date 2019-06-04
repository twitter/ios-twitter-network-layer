//
//  TNLGlobalConfiguration_Project.h
//  TwitterNetworkLayer
//
//  Created on 12/1/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#include <TargetConditionals.h>

#import "TNLGlobalConfiguration.h"

/*
 * NOTE: this header is private to TNL
 */

NS_ASSUME_NONNULL_BEGIN

@protocol TNLLogger;

typedef NSUInteger TNLBackgroundTaskIdentifier;
FOUNDATION_EXTERN const TNLBackgroundTaskIdentifier TNLBackgroundTaskInvalid;

@interface TNLGlobalConfiguration ();

@property (nonatomic, readonly) dispatch_queue_t configurationQueue;
@property (atomic, nullable) id<TNLLogger> internalLogger;
@property (atomic, copy, nullable, readonly) NSArray<id<TNLAuthenticationChallengeHandler>> * internalAuthenticationChallengeHandlers;
@property (atomic) TNLGlobalConfigurationURLSessionPruneOptions internalURLSessionPruneOptions;
@property (atomic) NSTimeInterval internalURLSessionInactivityThreshold;

#if TARGET_OS_IOS || TARGET_OS_TV
@property (atomic) UIApplicationState lastApplicationState;
#endif

- (TNLBackgroundTaskIdentifier)startBackgroundTaskWithName:(nullable NSString *)name
                                         expirationHandler:(void(^ __nullable)(void))handler;
- (void)endBackgroundTaskWithIdentifier:(TNLBackgroundTaskIdentifier)identifier;

@end

NS_ASSUME_NONNULL_END

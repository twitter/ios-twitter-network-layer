//
//  TNLGlobalConfiguration.m
//  TwitterNetworkLayer
//
//  Created on 11/21/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLBackoff.h"
#import "TNLGlobalConfiguration_Project.h"
#import "TNLLogger.h"
#import "TNLRequestOperationQueue_Project.h"

NS_ASSUME_NONNULL_BEGIN

NSTimeInterval const TNLGlobalConfigurationURLSessionInactivityThresholdDefault = 60.0 * 4.0; // four minutes
const TNLBackgroundTaskIdentifier TNLBackgroundTaskInvalid = 0;
static const TNLBackgroundTaskIdentifier TNLBackgroundTaskInitial = 1;

const NSTimeInterval TNLGlobalConfigurationRequestOperationCallbackTimeoutDefault = 10.0;

TNL_OBJC_FINAL TNL_OBJC_DIRECT_MEMBERS
@interface TNLBackgroundTaskHandleInternal : NSObject
@property (nonatomic, nullable, copy, readonly) void (^expirationHandler)(void);
@property (nonatomic, nullable, copy, readonly) NSString *name;
@property (nonatomic, readonly) TNLBackgroundTaskIdentifier taskIdentifier;
- (instancetype)initWithTaskIdentifier:(TNLBackgroundTaskIdentifier)taskId
                                  name:(nullable NSString *)name
                     expirationHandler:(void(^ __nullable)(void))handler;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@implementation TNLGlobalConfiguration
{
    TNLBackgroundTaskIdentifier _nextBackgroundTaskIdentifier;
    NSMutableDictionary<NSNumber *, TNLBackgroundTaskHandleInternal *> *_runningBackgroundTasks;
    dispatch_queue_t _backgroundTaskQueue;
    NSArray<id<TNLAuthenticationChallengeHandler>> *_authHandlers;
    id<TNLBackoffSignaler> _backoffSignaler;

#if TARGET_OS_IOS || TARGET_OS_TV
    UIBackgroundTaskIdentifier _sharedUIApplicationBackgroundTaskIdentifier;
#endif
}

+ (NSString *)version
{
    return TNLVersion();
}

+ (instancetype)sharedInstance
{
    static TNLGlobalConfiguration *sConfig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sConfig = [[TNLGlobalConfiguration alloc] initInternal];
    });
    return sConfig;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initInternal
{
    if (self = [super init]) {
        _configurationQueue = dispatch_queue_create("tnl.global.config.queue", DISPATCH_QUEUE_CONCURRENT);
        _requestOperationCallbackTimeout = TNLGlobalConfigurationRequestOperationCallbackTimeoutDefault;
        _backgroundTaskQueue = dispatch_queue_create("tnl.global.bg.task.queue", DISPATCH_QUEUE_SERIAL);
        _nextBackgroundTaskIdentifier = TNLBackgroundTaskInitial;
        _runningBackgroundTasks = [[NSMutableDictionary alloc] init];
        _idleTimeoutMode = TNLGlobalConfigurationIdleTimeoutModeDefault;
        _timeoutIntervalBetweenDataTransfer = 0.0;
        _operationAutomaticDependencyPriorityThreshold = (TNLPriority)NSIntegerMax;
        _internalURLSessionInactivityThreshold = TNLGlobalConfigurationURLSessionInactivityThresholdDefault;
        _backoffSignaler = [[TNLSimpleBackoffSignaler alloc] init];

#if TARGET_OS_IOS || TARGET_OS_TV
        _sharedUIApplicationBackgroundTaskIdentifier = 0;
        const Class UIApplicationClass = TNLDynamicUIApplicationClass();
        if (UIApplicationClass != Nil) {
            _sharedUIApplicationBackgroundTaskIdentifier = UIBackgroundTaskInvalid;

            NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
            [nc addObserver:self
                   selector:@selector(_tnl_applicationDidFinishLaunching:)
                       name:UIApplicationDidFinishLaunchingNotification
                     object:nil];
            [nc addObserver:self
                   selector:@selector(_tnl_applicationWillResignActive:)
                       name:UIApplicationWillResignActiveNotification
                     object:nil];
            [nc addObserver:self
                   selector:@selector(_tnl_applicationWillEnterForeground:)
                       name:UIApplicationWillEnterForegroundNotification
                     object:nil];
            [nc addObserver:self
                   selector:@selector(_tnl_applicationDidBecomeActive:)
                       name:UIApplicationDidBecomeActiveNotification
                     object:nil];
            [nc addObserver:self
                   selector:@selector(_tnl_applicationDidEnterBackground:)
                       name:UIApplicationDidEnterBackgroundNotification
                     object:nil];
            [nc addObserver:self
                   selector:@selector(_tnl_applicationDidReceiveMemoryWarning:)
                       name:UIApplicationDidReceiveMemoryWarningNotification
                     object:nil];

            UIApplication *sharedUIApplication = TNLDynamicUIApplicationSharedApplication();
            if (sharedUIApplication) {
                if ([NSThread isMainThread]) {
                    _lastApplicationState = sharedUIApplication.applicationState;
                } else {
                    _lastApplicationState = UIApplicationStateInactive;
                    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
                        self.lastApplicationState = sharedUIApplication.applicationState;
                    });
                }
            } else {
                // application can be `nil` if `TNLGlobalConfiguration` is accessed prior to app launch
                _lastApplicationState = UIApplicationStateBackground;
            }
        }
#endif // IOS + TV
    }
    return self;
}

#if TARGET_OS_IOS || TARGET_OS_TV

- (void)_tnl_applicationDidFinishLaunching:(NSNotification *)note
{
    UIApplication *application = note.object ?: TNLDynamicUIApplicationSharedApplication();
    self.lastApplicationState = application.applicationState;
}

- (void)_tnl_applicationWillResignActive:(NSNotification *)note
{
    self.lastApplicationState = UIApplicationStateInactive;
}

- (void)_tnl_applicationWillEnterForeground:(NSNotification *)note
{
    // When you adopt UIScene in iOS 13+, the foreground notification is sent
    // on both cold start and return from background. We only want to update
    // our application state for the latter
    if (self.lastApplicationState == UIApplicationStateBackground) {
        self.lastApplicationState = UIApplicationStateInactive;
    }
}

- (void)_tnl_applicationDidBecomeActive:(NSNotification *)note
{
    self.lastApplicationState = UIApplicationStateActive;
}

- (void)_tnl_applicationDidEnterBackground:(NSNotification *)note
{
    self.lastApplicationState = UIApplicationStateBackground;

    if (TNL_BITMASK_INTERSECTS_FLAGS(self.internalURLSessionPruneOptions, TNLGlobalConfigurationURLSessionPruneOptionOnApplicationBackground)) {
        [[TNLURLSessionManager sharedInstance] pruneUnusedURLSessions];
    }
}

- (void)_tnl_applicationDidReceiveMemoryWarning:(NSNotification *)note
{
    if (TNL_BITMASK_INTERSECTS_FLAGS(self.internalURLSessionPruneOptions, TNLGlobalConfigurationURLSessionPruneOptionOnMemoryWarning)) {
        [[TNLURLSessionManager sharedInstance] pruneUnusedURLSessions];
    }
}

#endif // IOS + TV

- (void)addNetworkObserver:(id<TNLNetworkObserver>)observer
{
    if (observer) {
        [TNLRequestOperationQueue addGlobalNetworkObserver:observer];
    }
}

- (void)removeNetworkObserver:(id<TNLNetworkObserver>)observer
{
    if (observer) {
        [TNLRequestOperationQueue removeGlobalNetworkObserver:observer];
    }
}

- (NSArray<id<TNLNetworkObserver>> *)allNetworkObservers
{
    return [TNLRequestOperationQueue allGlobalNetworkObservers];
}

- (void)addHeaderProvider:(id<TNLHTTPHeaderProvider>)provider
{
    if (provider) {
        [TNLRequestOperationQueue addGlobalHeaderProvider:provider];
    }
}

- (void)removeHeaderProvider:(id<TNLHTTPHeaderProvider>)provider
{
    if (provider) {
        [TNLRequestOperationQueue removeGlobalHeaderProvider:provider];
    }
}

- (NSArray<id<TNLHTTPHeaderProvider>> *)allHeaderProviders
{
    return [TNLRequestOperationQueue allGlobalHeaderProviders];
}

- (TNLGlobalConfigurationBackoffMode)backoffMode
{
    return [TNLURLSessionManager sharedInstance].backoffMode;
}

- (void)setBackoffMode:(TNLGlobalConfigurationBackoffMode)mode
{
    [TNLURLSessionManager sharedInstance].backoffMode = mode;
}

- (id<TNLBackoffBehaviorProvider>)backoffBehaviorProvider
{
    return [TNLURLSessionManager sharedInstance].backoffBehaviorProvider;
}

- (void)setBackoffBehaviorProvider:(nullable id<TNLBackoffBehaviorProvider>)provider
{
    [TNLURLSessionManager sharedInstance].backoffBehaviorProvider = provider;
}

- (id<TNLBackoffSignaler>)backoffSignaler
{
    if (dispatch_queue_get_label(tnl_network_queue()) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)) {
        return _backoffSignaler;
    }

    __block id<TNLBackoffSignaler> signaler = nil;
    dispatch_sync(tnl_network_queue(), ^{
        signaler = self->_backoffSignaler;
    });
    return signaler;
}

- (void)setBackoffSignaler:(nullable id<TNLBackoffSignaler>)backoffSignaler
{
    if (!backoffSignaler) {
        backoffSignaler = [[TNLSimpleBackoffSignaler alloc] init];
    }

    if (dispatch_queue_get_label(tnl_network_queue()) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)) {
        _backoffSignaler = backoffSignaler;
        return;
    }

    dispatch_async(tnl_network_queue(), ^{
        self->_backoffSignaler = backoffSignaler;
    });
}

- (TNLGlobalConfigurationURLSessionPruneOptions)URLSessionPruneOptions
{
    return self.internalURLSessionPruneOptions;
}

- (void)setURLSessionPruneOptions:(TNLGlobalConfigurationURLSessionPruneOptions)URLSessionPruneOptions
{
    if (TNLGlobalConfigurationURLSessionPruneOptionNow == URLSessionPruneOptions) {
        [[TNLURLSessionManager sharedInstance] pruneUnusedURLSessions];
        return;
    }

    self.internalURLSessionPruneOptions = URLSessionPruneOptions;
}

- (NSTimeInterval)URLSessionInactivityThreshold
{
    return self.internalURLSessionInactivityThreshold;
}

- (void)setURLSessionInactivityThreshold:(NSTimeInterval)URLSessionInactivityThreshold
{
    if (URLSessionInactivityThreshold < 0.0) {
        URLSessionInactivityThreshold = TNLGlobalConfigurationURLSessionInactivityThresholdDefault;
    }
    self.internalURLSessionInactivityThreshold = URLSessionInactivityThreshold;
}

- (void)pruneURLSessionMatchingRequestConfiguration:(TNLRequestConfiguration *)config
                                   operationQueueId:(nullable NSString *)operationQueueId
{
    [[TNLURLSessionManager sharedInstance] pruneURLSessionMatchingRequestConfiguration:config
                                                                      operationQueueId:operationQueueId];
}

- (void)setLogger:(nullable id<TNLLogger>)logger
{
    gTNLLogger = logger;
    self.internalLogger = logger;
}

- (nullable id<TNLLogger>)logger
{
    return self.internalLogger;
}

- (void)setAssertsEnabled:(BOOL)assertsEnabled
{
    gTwitterNetworkLayerAssertEnabled = assertsEnabled;
}

- (BOOL)areAssertsEnabled
{
    return gTwitterNetworkLayerAssertEnabled;
}

- (void)addAuthenticationChallengeHandler:(id<TNLAuthenticationChallengeHandler>)handler
{
    dispatch_barrier_async(_configurationQueue, ^{
        @autoreleasepool {
            if (!self->_authHandlers) {
                self->_authHandlers = @[handler];
            } else if (![self->_authHandlers containsObject:handler]) {
                self->_authHandlers = [self->_authHandlers arrayByAddingObject:handler];
            }
        }
    });
}

- (void)removeAuthenticationChallengeHandler:(id<TNLAuthenticationChallengeHandler>)handler
{
    dispatch_barrier_async(_configurationQueue, ^{
        @autoreleasepool {
            if (self->_authHandlers) {
                NSMutableArray<id<TNLAuthenticationChallengeHandler>> *handlers = [self->_authHandlers mutableCopy];
                [handlers removeObject:handler];
                self->_authHandlers = (handlers.count > 0) ? [handlers copy] : nil;
            }
        }
    });
}

- (nullable NSArray<id<TNLAuthenticationChallengeHandler>> *)internalAuthenticationChallengeHandlers
{
    __block NSArray<id<TNLAuthenticationChallengeHandler>> *handlers;
    dispatch_sync(self->_configurationQueue, ^{
        handlers = self->_authHandlers;
    });
    return handlers;
}

#pragma mark Background Tasks

- (TNLBackgroundTaskIdentifier)startBackgroundTaskWithName:(nullable NSString *)name
                                         expirationHandler:(void(^ __nullable)(void))handler
{
    __block TNLBackgroundTaskIdentifier identifier;
    dispatch_sync(_backgroundTaskQueue, ^{
        identifier = self->_nextBackgroundTaskIdentifier++;
        if (identifier == TNLBackgroundTaskInvalid) {
            TNLLogWarning(@"Background Task Identifier pool has been exhausted, restarting.");
            identifier = TNLBackgroundTaskInitial;
            self->_nextBackgroundTaskIdentifier = identifier + 1;
        }
    });

    dispatch_block_t block = ^{
        [self _main_ensureSharedBackgroundTask];

        TNLBackgroundTaskHandleInternal *handle = [[TNLBackgroundTaskHandleInternal alloc] initWithTaskIdentifier:identifier
                                                                                                             name:name
                                                                                                expirationHandler:handler];
        self->_runningBackgroundTasks[@(identifier)] = handle;
    };

    if ([NSThread isMainThread]) {
        block();
    } else {
        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), block);
    }

    return identifier;
}

- (void)endBackgroundTaskWithIdentifier:(TNLBackgroundTaskIdentifier)identifier
{
    SEL cmdSelector = _cmd;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        if (identifier == TNLBackgroundTaskInvalid) {
            TNLLogWarning(@"Cannot call [%@ %@] with invalid identifier!", NSStringFromClass([self class]), NSStringFromSelector(cmdSelector));
            return;
        }

        TNLBackgroundTaskHandleInternal *handle = self->_runningBackgroundTasks[@(identifier)];
        if (!handle) {
            TNLLogWarning(@"[%@ %@%tu] Background Task Identifier was not started or already ended!", NSStringFromClass([self class]), NSStringFromSelector(cmdSelector), identifier);
            return;
        }

        [self->_runningBackgroundTasks removeObjectForKey:@(identifier)];
        [self _main_cleanUpSharedBackgroundTaskIfNecessary];
    });
}

- (void)_main_ensureSharedBackgroundTask TNL_OBJC_DIRECT
{
#if TARGET_OS_IOS || TARGET_OS_TV
    UIApplication *sharedUIApplication = TNLDynamicUIApplicationSharedApplication();
    if (sharedUIApplication) {
        if (UIBackgroundTaskInvalid == _sharedUIApplicationBackgroundTaskIdentifier) {
            _sharedUIApplicationBackgroundTaskIdentifier = [sharedUIApplication beginBackgroundTaskWithName:@"tnl.global.shared.bg.task" expirationHandler:^{
                [self _handleExpiration];
            }];
        }
    }
#endif // IOS + TV
}

- (void)_main_cleanUpSharedBackgroundTaskIfNecessary TNL_OBJC_DIRECT
{
#if TARGET_OS_IOS || TARGET_OS_TV
    UIApplication *sharedUIApplication = TNLDynamicUIApplicationSharedApplication();
    if (sharedUIApplication) {
        if (_sharedUIApplicationBackgroundTaskIdentifier != UIBackgroundTaskInvalid && _runningBackgroundTasks.count == 0) {
            UIBackgroundTaskIdentifier identifier = _sharedUIApplicationBackgroundTaskIdentifier;
            _sharedUIApplicationBackgroundTaskIdentifier = UIBackgroundTaskInvalid;
            [sharedUIApplication endBackgroundTask:identifier];
        }
    }
#endif // IOS + TV
}

#if TARGET_OS_IOS || TARGET_OS_TV
- (void)_handleExpiration TNL_OBJC_DIRECT
{
    UIApplication *sharedUIApplication = TNLDynamicUIApplicationSharedApplication();
    if (sharedUIApplication) {
        dispatch_block_t block = ^{
            for (TNLBackgroundTaskHandleInternal *handle in self->_runningBackgroundTasks.allValues) {
                TNLLogWarning(@"Background Task Expired! '%@'", handle.name ?: @"???");
                if (handle.expirationHandler) {
                    handle.expirationHandler();
                }
            }
            [self->_runningBackgroundTasks removeAllObjects];
            [self _main_cleanUpSharedBackgroundTaskIfNecessary];
        };

        if ([NSThread isMainThread]) {
            block();
        } else {
            tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), block);
        }
    }
}
#endif // IOS + TV

@end

@implementation TNLGlobalConfiguration (Debugging)

- (NSArray<TNLRequestOperation *> *)allRequestOperations
{
    NSArray<NSOperation *> *ops = [TNLRequestOperationQueue globalRequestOperationQueue].operations;
    NSMutableArray<TNLRequestOperation *> *tnlOps = [[NSMutableArray alloc] init];
    for (NSOperation *op in ops) {
        if ([op isKindOfClass:[TNLRequestOperation class]]) {
            [tnlOps addObject:(id)op];
        }
    }
    return [tnlOps copy];
}

@end

@implementation TNLBackgroundTaskHandleInternal

- (instancetype)initWithTaskIdentifier:(TNLBackgroundTaskIdentifier)taskId
                                  name:(nullable NSString *)name
                     expirationHandler:(nullable void (^)(void))handler
{
    TNLAssert(TNLBackgroundTaskInvalid != taskId);
    if (self = [super init]) {
        _name = [name copy];
        _expirationHandler = [handler copy];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END

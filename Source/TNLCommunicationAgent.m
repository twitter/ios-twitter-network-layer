//
//  TNLCommunicationAgent.m
//  TwitterNetworkLayer
//
//  Created on 5/2/16.
//  Copyright © 2020 Twitter. All rights reserved.
//

#include <TargetConditionals.h>

#if !TARGET_OS_WATCH // no communication agent for watchOS

#import <Network/Network.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import "NSDictionary+TNLAdditions.h"
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLCommunicationAgent_Project.h"
#import "TNLHTTP.h"
#import "TNLPseudoURLProtocol.h"

#define FORCE_LOG_REACHABILITY_CHANGE 0

static const NSTimeInterval kCaptivePortalQuietTime = 60.0;
static NSString * const kCaptivePortalCheckEndpoint = @"http://connectivitycheck.gstatic.com/generate_204";

static void _ReachabilityCallback(__unused SCNetworkReachabilityRef target,
                                  const SCNetworkReachabilityFlags flags,
                                  void* info);
static TNLNetworkReachabilityStatus _NetworkReachabilityStatusFromFlags(TNLNetworkReachabilityFlags flags) __attribute__((const));
static TNLNetworkReachabilityFlags _NetworkReachabilityFlagsFromPath(nw_path_t path);
static BOOL _HasCellularInterface(void);

#define _NWPathStatusToFlag(status) ((status > 0) ? ((uint32_t)1 << (uint32_t)((status) - 1)) : 0)
#define _NWInterfaceTypeToFlag(itype) ((uint32_t)1 << (uint32_t)8 << (uint32_t)(itype))

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"

TNLStaticAssert(_NWPathStatusToFlag(nw_path_status_satisfied) == TNLNetworkReachabilityMaskPathStatusSatisfied, MISSMATCH_REACHABILITY_FLAGS);
TNLStaticAssert(_NWPathStatusToFlag(nw_path_status_unsatisfied) == TNLNetworkReachabilityMaskPathStatusUnsatisfied, MISSMATCH_REACHABILITY_FLAGS);
TNLStaticAssert(_NWPathStatusToFlag(nw_path_status_satisfiable) == TNLNetworkReachabilityMaskPathStatusSatisfiable, MISSMATCH_REACHABILITY_FLAGS);

TNLStaticAssert(_NWInterfaceTypeToFlag(nw_interface_type_other) == TNLNetworkReachabilityMaskPathIntefaceTypeOther, MISSMATCH_REACHABILITY_FLAGS);
TNLStaticAssert(_NWInterfaceTypeToFlag(nw_interface_type_wifi) == TNLNetworkReachabilityMaskPathIntefaceTypeWifi, MISSMATCH_REACHABILITY_FLAGS);
TNLStaticAssert(_NWInterfaceTypeToFlag(nw_interface_type_cellular) == TNLNetworkReachabilityMaskPathIntefaceTypeCellular, MISSMATCH_REACHABILITY_FLAGS);
TNLStaticAssert(_NWInterfaceTypeToFlag(nw_interface_type_wired) == TNLNetworkReachabilityMaskPathIntefaceTypeWired, MISSMATCH_REACHABILITY_FLAGS);
TNLStaticAssert(_NWInterfaceTypeToFlag(nw_interface_type_loopback) == TNLNetworkReachabilityMaskPathIntefaceTypeLoopback, MISSMATCH_REACHABILITY_FLAGS);

#pragma clang diagnostic pop

TNL_OBJC_FINAL TNL_OBJC_DIRECT_MEMBERS
@interface TNLCommunicationAgentWeakWrapper : NSObject
@property (nonatomic, weak) TNLCommunicationAgent *communicationAgent;
@end

@interface TNLCommunicationAgent ()

@property (atomic) TNLNetworkReachabilityStatus currentReachabilityStatus;
@property (atomic) TNLNetworkReachabilityFlags currentReachabilityFlags;
@property (atomic, copy, nullable) NSString *currentWWANRadioAccessTechnology;
@property (atomic) TNLCaptivePortalStatus currentCaptivePortalStatus;
@property (atomic, nullable) id<TNLCarrierInfo> currentCarrierInfo;

@end

TNL_OBJC_DIRECT_MEMBERS
@interface TNLCommunicationAgent (Agent)

- (void)_agent_initialize;
- (void)_agent_initializeLegacyReachability;
- (void)_agent_initializeModernReachability;
- (void)_agent_initializeTelephony;
- (void)_agent_updateModernReachabilityWithNetworkPath:(nonnull nw_path_t)path;
- (void)_agent_forciblyUpdateLegacyReachability;
- (void)_agent_updateReachabilityFlags:(TNLNetworkReachabilityFlags)newFlags
                                status:(TNLNetworkReachabilityStatus)newStatus;

- (void)_agent_addObserver:(id<TNLCommunicationAgentObserver>)observer;
- (void)_agent_removeObserver:(id<TNLCommunicationAgentObserver>)observer;

- (void)_agent_identifyReachability:(TNLCommunicationAgentIdentifyReachabilityCallback)callback;
- (void)_agent_identifyCarrierInfo:(TNLCommunicationAgentIdentifyCarrierInfoCallback)callback;
- (void)_agent_identifyWWANRadioAccessTechnology:(TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback)callback;
- (void)_agent_identifyCaptivePortalStatus:(TNLCommunicationAgentIdentifyCaptivePortalStatusCallback)callback;

- (void)_agent_startCaptivePortalCheckTimerWithDelay:(NSTimeInterval)delay;
- (void)_agent_triggerCaptivePortalCheck;
- (void)_agent_triggerCaptivePortalCheckIfNeeded;
- (void)_agent_handleCaptivePortalResponse:(nullable NSHTTPURLResponse *)response
                                      data:(nullable NSData *)data
                                  dataTask:(nullable NSURLSessionDataTask *)dataTask
                                     error:(nullable NSError *)error;

@end

@interface TNLCommunicationAgent (Private)
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
- (void)_updateCarrier:(CTCarrier *)carrier TNL_OBJC_DIRECT;
#endif
- (void)private_updateRadioAccessTechnology:(NSNotification *)note;
@end

@implementation TNLCommunicationAgent
{
    NSMutableArray<id<TNLCommunicationAgentObserver>> *_queuedObservers;
    NSMutableArray<TNLCommunicationAgentIdentifyReachabilityCallback> *_queuedReachabilityCallbacks;
    NSMutableArray<TNLCommunicationAgentIdentifyCarrierInfoCallback> *_queuedCarrierInfoCallbacks;
    NSMutableArray<TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback> *_queuedRadioTechInfoCallbacks;
    NSMutableArray<TNLCommunicationAgentIdentifyCaptivePortalStatusCallback> *_queuedCaptivePortalCallbacks;

    NSMutableArray<TNLCommunicationAgentIdentifyCaptivePortalStatusCallback> *_captivePortalCheckCallbacks;

    NSHashTable<id<TNLCommunicationAgentObserver>> *_observers;

    dispatch_queue_t _agentQueue;
    NSOperationQueue *_agentOperationQueue;
    TNLCommunicationAgentWeakWrapper *_agentWrapper;

    SCNetworkReachabilityRef _legacyReachabilityRef;
    nw_path_monitor_t _modernReachabilityNetworkPathMonitor; // supports ARC

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    CTTelephonyNetworkInfo *_internalTelephonyNetworkInfo;
#endif
    NSURLSessionConfiguration *_captivePortalSessionConfiguration;
    NSURLSessionDataTask *_captivePortalTask;
    NSDate *_lastCaptivePortalCheck;
    struct {
        BOOL initialized:1;
        BOOL initializedReachability:1;
        BOOL initializedCarrier:1;
        BOOL initializedRadioTech:1;
    } _flags;
}

+ (BOOL)hasCellularInterface
{
    static BOOL sHasCellular = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sHasCellular = _HasCellularInterface();
    });
    return sHasCellular;
}

- (instancetype)initWithInternetReachabilityHost:(NSString *)host
{
    TNLAssert(host != nil);
    if (!host) {
        return nil;
    }

    if (self = [super init]) {
        _host = [host copy];
        _observers = [NSHashTable weakObjectsHashTable];
        _queuedObservers = [[NSMutableArray alloc] init];
        _queuedReachabilityCallbacks = [[NSMutableArray alloc] init];
        _queuedCarrierInfoCallbacks = [[NSMutableArray alloc] init];
        _queuedRadioTechInfoCallbacks = [[NSMutableArray alloc] init];
        _queuedCaptivePortalCallbacks = [[NSMutableArray alloc] init];
        _captivePortalCheckCallbacks = [[NSMutableArray alloc] init];
        _agentQueue = dispatch_queue_create("TNLCommunicationAgent.queue", DISPATCH_QUEUE_SERIAL);
        _agentOperationQueue = [[NSOperationQueue alloc] init];
        _agentOperationQueue.name = @"TNLCommunicationAgent.queue";
        _agentOperationQueue.maxConcurrentOperationCount = 1;
        _agentOperationQueue.underlyingQueue = _agentQueue;
        _agentOperationQueue.qualityOfService = NSQualityOfServiceUtility;
        _agentWrapper = [[TNLCommunicationAgentWeakWrapper alloc] init];
        _agentWrapper.communicationAgent = self;

        tnl_dispatch_async_autoreleasing(_agentQueue, ^{
            [self _agent_initialize];
        });
    }

    return self;
}

- (void)dealloc
{
    if (_legacyReachabilityRef) {
        SCNetworkReachabilitySetCallback(_legacyReachabilityRef, NULL, NULL);
        SCNetworkReachabilitySetDispatchQueue(_legacyReachabilityRef, NULL);
        CFRelease(_legacyReachabilityRef);
    }
    if (tnl_available_ios_12) {
        if (_modernReachabilityNetworkPathMonitor) {
            nw_path_monitor_cancel(_modernReachabilityNetworkPathMonitor);
        }
    }

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:CTRadioAccessTechnologyDidChangeNotification
                                                  object:nil];
#endif

    // Give the SCNetworkReachability callbacks time to flush.
    //
    // Since the weak wrapper is used for the context of the reachability function callback it means
    // there needs to be a strong reference when that callback is executed.
    // We clear the callback above, but due to async behavior, the weak wrapper reference could
    // still be lingering to a callback.
    // Thus, we'll ensure that the weak wrapper instance is strongly held beyond the lifetime of the
    // dealloc so that it survives longer than any callbacks that are triggered.
    // Assigning communicationAgent to nil is really an arbitrary method call in order to keep the
    // strong reference around, and is effectively a no-op.

    dispatch_queue_t agentQueue = _agentQueue;
    TNLCommunicationAgentWeakWrapper *weakWrapper = _agentWrapper;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), agentQueue, ^{
        tnl_dispatch_async_autoreleasing(agentQueue, ^{
            weakWrapper.communicationAgent = nil;
        });
    });
}

- (void)addObserver:(id<TNLCommunicationAgentObserver>)observer
{
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        [self _agent_addObserver:observer];
    });
}

- (void)removeObserver:(id<TNLCommunicationAgentObserver>)observer
{
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        [self _agent_removeObserver:observer];
    });
}

- (void)identifyReachability:(TNLCommunicationAgentIdentifyReachabilityCallback)callback
{
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        [self _agent_identifyReachability:callback];
    });
}

- (void)identifyCarrierInfo:(TNLCommunicationAgentIdentifyCarrierInfoCallback)callback
{
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        [self _agent_identifyCarrierInfo:callback];
    });
}

- (void)identifyWWANRadioAccessTechnology:(TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback)callback
{
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        [self _agent_identifyWWANRadioAccessTechnology:callback];
    });
}

- (void)identifyCaptivePortalStatus:(TNLCommunicationAgentIdentifyCaptivePortalStatusCallback)callback
{
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        [self _agent_identifyCaptivePortalStatus:callback];
    });
}

@end

TNL_OBJC_DIRECT_MEMBERS
@implementation TNLCommunicationAgent (Agent)

#pragma mark Legacy Reachability

- (void)_agent_forciblyUpdateLegacyReachability
{
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(_legacyReachabilityRef, &flags)) {
        self.currentReachabilityFlags = flags;
        self.currentReachabilityStatus = _NetworkReachabilityStatusFromFlags(flags);
    } else {
        self.currentReachabilityFlags = 0;
        self.currentReachabilityStatus = TNLNetworkReachabilityUndetermined;
    }
}

- (void)_agent_initializeLegacyReachability
{
    _legacyReachabilityRef = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, self.host.UTF8String);

    [self _agent_forciblyUpdateLegacyReachability];

    SCNetworkReachabilityContext context = { 0, (__bridge void*)_agentWrapper, NULL, NULL, NULL };
    if (SCNetworkReachabilitySetCallback(_legacyReachabilityRef, _ReachabilityCallback, &context)) {
        if (SCNetworkReachabilitySetDispatchQueue(_legacyReachabilityRef, _agentQueue)) {
            _flags.initializedReachability = 1;
        } else {
            SCNetworkReachabilitySetCallback(_legacyReachabilityRef, NULL, NULL);
            CFRelease(_legacyReachabilityRef);
            _legacyReachabilityRef = NULL;
        }
    }

    if (!_flags.initializedReachability) {
        TNLLogError(@"Failed to start reachability: %@", self.host);
        if (_legacyReachabilityRef) {
            CFRelease(_legacyReachabilityRef);
            _legacyReachabilityRef = NULL;
        }
    }
}

#pragma mark Modern Reachability

- (void)_agent_updateModernReachabilityWithNetworkPath:(nonnull nw_path_t)path
{
    if (tnl_available_ios_12) {

#if DEBUG
        TNLLogDebug(@"network path monitor update: %@", path.description);
#endif

        const TNLNetworkReachabilityFlags newFlags = _NetworkReachabilityFlagsFromPath(path);
        const TNLNetworkReachabilityStatus newStatus = _NetworkReachabilityStatusFromFlags(newFlags);
        [self _agent_updateReachabilityFlags:newFlags status:newStatus];
    }
}

- (void)_agent_initializeModernReachability
{
    if (tnl_available_ios_12) {
        __weak typeof(self) weakSelf = self;
        _modernReachabilityNetworkPathMonitor = nw_path_monitor_create();

        nw_path_monitor_set_queue(_modernReachabilityNetworkPathMonitor, _agentQueue);
        // nw_path_monitor_set_cancel_handler // don't need a cancel handler
        nw_path_monitor_set_update_handler(_modernReachabilityNetworkPathMonitor, ^(nw_path_t  __nonnull path) {
            [weakSelf _agent_updateModernReachabilityWithNetworkPath:path];
        });

        nw_path_monitor_start(_modernReachabilityNetworkPathMonitor); // will trigger an update callback (but async)

        _flags.initializedReachability = 1;
    }
}

#pragma mark Telephony

- (void)_agent_initializeTelephony
{
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    __weak typeof(self) weakSelf = self;

    _internalTelephonyNetworkInfo = [[CTTelephonyNetworkInfo alloc] init];
    _internalTelephonyNetworkInfo.subscriberCellularProviderDidUpdateNotifier = ^(CTCarrier *carrier) {
        [weakSelf _updateCarrier:carrier];
    };
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(private_updateRadioAccessTechnology:)
                                                 name:CTRadioAccessTechnologyDidChangeNotification object:nil];
    self.currentCarrierInfo = [TNLCarrierInfoInternal carrierWithCarrier:_internalTelephonyNetworkInfo.subscriberCellularProvider];
    self.currentWWANRadioAccessTechnology = [_internalTelephonyNetworkInfo.currentRadioAccessTechnology copy];
#endif // #if TARGET_OS_IOS && !TARGET_OS_MACCATALYST

    _flags.initializedCarrier = 1;
    _flags.initializedRadioTech = 1;
}

#pragma mark Captive Portal

- (void)_agent_initializeCaptivePortalStatus
{
    self.currentCaptivePortalStatus = TNLCaptivePortalStatusUndetermined;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30;
    config.timeoutIntervalForResource = 30;
    config.URLCache = nil;
    config.URLCredentialStorage = nil;
    config.HTTPCookieStorage = nil;
    config.TLSMinimumSupportedProtocol = 0;
    config.TLSMaximumSupportedProtocol = 0;
    config.allowsCellularAccess = YES;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.HTTPShouldSetCookies = NO;
    config.HTTPMaximumConnectionsPerHost = 1;
    [config tnl_insertProtocolClasses:@[[TNLPseudoURLProtocol class]]];

    _captivePortalSessionConfiguration = [config copy];
    TNLCommunicationAgentIdentifyCaptivePortalStatusCallback callback = ^(TNLCaptivePortalStatus status) {
        // nothing
    };
    [_queuedCaptivePortalCallbacks addObject:[callback copy]];
}

#pragma mark Private Methods

- (void)_agent_initialize
{
    TNLAssert(!_flags.initialized);
    TNLAssert(!_flags.initializedReachability);
    TNLAssert(!_flags.initializedCarrier);
    TNLAssert(!_flags.initializedRadioTech);
    TNLAssert(!_legacyReachabilityRef);
    TNLAssert(!_modernReachabilityNetworkPathMonitor);

    if (tnl_available_ios_12) {
        [self _agent_initializeModernReachability];
    } else {
        [self _agent_initializeLegacyReachability];
    }
    [self _agent_initializeTelephony];
    [self _agent_initializeCaptivePortalStatus];

    NSArray<id<TNLCommunicationAgentObserver>> *queuedObservers = [_queuedObservers copy];
    NSArray<TNLCommunicationAgentIdentifyReachabilityCallback> *reachBlocks = [_queuedReachabilityCallbacks copy];
    NSArray<TNLCommunicationAgentIdentifyCarrierInfoCallback> *carrierBlocks = [_queuedCarrierInfoCallbacks copy];
    NSArray<TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback> *radioBlocks = [_queuedRadioTechInfoCallbacks copy];
    NSArray<TNLCommunicationAgentIdentifyCaptivePortalStatusCallback> *captivePortalBlocks = [_queuedCaptivePortalCallbacks copy];

    _queuedObservers = nil;
    _queuedReachabilityCallbacks = nil;
    _queuedCarrierInfoCallbacks = nil;
    _queuedRadioTechInfoCallbacks = nil;
    _queuedCaptivePortalCallbacks = nil;

    _flags.initialized = 1;

    for (id<TNLCommunicationAgentObserver> observer in queuedObservers) {
        [self _agent_addObserver:observer];
    }
    for (TNLCommunicationAgentIdentifyReachabilityCallback block in reachBlocks) {
        [self _agent_identifyReachability:block];
    }
    for (TNLCommunicationAgentIdentifyCarrierInfoCallback block in carrierBlocks) {
        [self _agent_identifyCarrierInfo:block];
    }
    for (TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback block in radioBlocks) {
        [self _agent_identifyWWANRadioAccessTechnology:block];
    }
    for (TNLCommunicationAgentIdentifyCaptivePortalStatusCallback block in captivePortalBlocks) {
        [self _agent_identifyCaptivePortalStatus:block];
    }
}

- (void)_agent_addObserver:(id<TNLCommunicationAgentObserver>)observer
{
    if (!_flags.initialized) {
        [_queuedObservers addObject:observer];
        return;
    }

    [_observers addObject:observer];

    static SEL legacySelector = nil;
    static SEL modernSelector = nil;
    if (!legacySelector || !modernSelector) {
        legacySelector = NSSelectorFromString(@"tnl_communicationAgent:didRegisterObserverWithInitialReachabilityFlags:status:carrierInfo:WWANRadioAccessTechnology:");
        modernSelector = @selector(tnl_communicationAgent:didRegisterObserverWithInitialReachabilityFlags:status:carrierInfo:WWANRadioAccessTechnology:captivePortalStatus:);
        // TODO: once TNL moves to version 3.0, remove this legacy selector safety check
    }

    if ([observer respondsToSelector:modernSelector]) {
        TNLNetworkReachabilityFlags flags = self.currentReachabilityFlags;
        TNLNetworkReachabilityStatus status = self.currentReachabilityStatus;
        id<TNLCarrierInfo> info = self.currentCarrierInfo;
        NSString *radioTech = self.currentWWANRadioAccessTechnology;
        TNLCaptivePortalStatus portalStatus = self.currentCaptivePortalStatus;
        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            [observer tnl_communicationAgent:self
                      didRegisterObserverWithInitialReachabilityFlags:flags
                      status:status
                      carrierInfo:info
                      WWANRadioAccessTechnology:radioTech
                      captivePortalStatus:portalStatus];
        });
    } else if ([observer respondsToSelector:legacySelector]) {
        TNLLogError(@"Method signature of TNLCommunicationAgentObserver callback has changed!  Please update from `%@` to `%@`", NSStringFromSelector(legacySelector), NSStringFromSelector(modernSelector));
        TNLAssertMessage(NO, @"Method signature of TNLCommunicationAgentObserver callback has changed!  Please update from `%@` to `%@`", NSStringFromSelector(legacySelector), NSStringFromSelector(modernSelector));
    }
}

- (void)_agent_removeObserver:(id<TNLCommunicationAgentObserver>)observer
{
    if (!_flags.initialized) {
        [_queuedObservers removeObject:observer];
        return;
    }

    [_observers removeObject:observer];
}

- (void)_agent_identifyReachability:(TNLCommunicationAgentIdentifyReachabilityCallback)callback
{
    if (!_flags.initialized) {
        [_queuedReachabilityCallbacks addObject:callback];
        return;
    }

    TNLNetworkReachabilityFlags flags = self.currentReachabilityFlags;
    TNLNetworkReachabilityStatus status = self.currentReachabilityStatus;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        callback(flags, status);
    });
}

- (void)_agent_identifyCarrierInfo:(TNLCommunicationAgentIdentifyCarrierInfoCallback)callback
{
    if (!_flags.initialized) {
        [_queuedCarrierInfoCallbacks addObject:callback];
        return;
    }

    id<TNLCarrierInfo> info = self.currentCarrierInfo;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        callback(info);
    });
}

- (void)_agent_identifyWWANRadioAccessTechnology:(TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback)callback
{
    if (!_flags.initialized) {
        [_queuedRadioTechInfoCallbacks addObject:callback];
        return;
    }

    NSString *radioTech = self.currentWWANRadioAccessTechnology;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        callback(radioTech);
    });
}

- (void)_agent_identifyCaptivePortalStatus:(TNLCommunicationAgentIdentifyCaptivePortalStatusCallback)callback
{
    if (!_flags.initialized) {
        [_queuedCaptivePortalCallbacks addObject:callback];
        return;
    }

    const TNLCaptivePortalStatus status = self.currentCaptivePortalStatus;
    if (status != TNLCaptivePortalStatusUndetermined) {
        callback(status);
        return;
    }

    [_captivePortalCheckCallbacks addObject:callback];
    [self _agent_triggerCaptivePortalCheckIfNeeded];
}

- (void)_agent_startCaptivePortalCheckTimerWithDelay:(NSTimeInterval)delay
{
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _agentQueue, ^{
        @autoreleasepool {
            [weakSelf _agent_triggerCaptivePortalCheckIfNeeded];
        }
    });
}

- (void)_agent_triggerCaptivePortalCheck
{
    _lastCaptivePortalCheck = nil; // clear to force the check
    [self _agent_triggerCaptivePortalCheckIfNeeded];
}

- (void)_agent_triggerCaptivePortalCheckIfNeeded
{
    if (_captivePortalTask) {
        // already running
        return;
    }

    if (_lastCaptivePortalCheck) {
        const NSTimeInterval delay = kCaptivePortalQuietTime - [[NSDate date] timeIntervalSinceDate:_lastCaptivePortalCheck];
        if (delay > 0.0) {
            // ran recently
            [self _agent_startCaptivePortalCheckTimerWithDelay:delay];
            return;
        }
    }

    // create a new session every time we check the captive portal state to avoid reusing connections
    NSURLSession *session = [NSURLSession sessionWithConfiguration:_captivePortalSessionConfiguration
                                                          delegate:nil
                                                     delegateQueue:_agentOperationQueue];
    __weak typeof(self) weakSelf = self;
    __block NSURLSessionDataTask *dataTask = nil;
    dataTask = [session dataTaskWithURL:[NSURL URLWithString:kCaptivePortalCheckEndpoint]
                      completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                            [weakSelf _agent_handleCaptivePortalResponse:(NSHTTPURLResponse *)response
                                                                    data:data
                                                                dataTask:dataTask
                                                                   error:error];
                      }];
    _captivePortalTask = dataTask;
    [dataTask resume];
}

- (void)_agent_handleCaptivePortalResponse:(nullable NSHTTPURLResponse *)response
                                      data:(nullable NSData *)data
                                  dataTask:(nullable NSURLSessionDataTask *)dataTask
                                     error:(nullable NSError *)error
{
    if (dataTask != _captivePortalTask) {
        return;
    }

    _captivePortalTask = nil;
    _lastCaptivePortalCheck = [NSDate date];
    [self _agent_startCaptivePortalCheckTimerWithDelay:kCaptivePortalQuietTime];

    TNLCaptivePortalStatus status = TNLCaptivePortalStatusNoCaptivePortal;
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection) {
        status = TNLCaptivePortalStatusDetectionBlockedByAppTransportSecurity;
    } else if (response) {
        const BOOL captive = (response.statusCode != TNLHTTPStatusCodeNoContent)
                                || (data.length > 0)
                                || ([[response.allHeaderFields tnl_objectForCaseInsensitiveKey:@"content-length"] integerValue] > 0);
        if (captive) {
            status = TNLCaptivePortalStatusCaptivePortalDetected;
        }
    }

    const TNLCaptivePortalStatus oldStatus = self.currentCaptivePortalStatus;
    if (oldStatus == status) {
        return;
    }

    self.currentCaptivePortalStatus = status;
    NSArray<TNLCommunicationAgentIdentifyCaptivePortalStatusCallback> *callbacks = [_captivePortalCheckCallbacks copy];
    [_captivePortalCheckCallbacks removeAllObjects];

    NSArray<id<TNLCommunicationAgentObserver>> *observers = _observers.allObjects;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        for (TNLCommunicationAgentIdentifyCaptivePortalStatusCallback callback in callbacks) {
            callback(status);
        }
        for (id<TNLCommunicationAgentObserver> observer in observers) {
            if ([observer respondsToSelector:@selector(tnl_communicationAgent:didUpdateCaptivePortalStatusFromPreviousStatus:toCurrentStatus:)]) {
                [observer tnl_communicationAgent:self
  didUpdateCaptivePortalStatusFromPreviousStatus:oldStatus
                                 toCurrentStatus:status];
            }
        }
    });
}

- (void)_agent_updateReachabilityFlags:(TNLNetworkReachabilityFlags)newFlags
                                status:(TNLNetworkReachabilityStatus)newStatus
{
    const TNLNetworkReachabilityFlags oldFlags = self.currentReachabilityFlags;
    const TNLNetworkReachabilityStatus oldStatus = self.currentReachabilityStatus;

    if (oldFlags == newFlags && oldStatus == newStatus) {
        return;
    }

    self.currentReachabilityStatus = newStatus;
    self.currentReachabilityFlags = newFlags;

#if FORCE_LOG_REACHABILITY_CHANGE
    NSLog(@"reachability change: %@", TNLDebugStringFromNetworkReachabilityFlags(newFlags));
#endif

    [self _agent_triggerCaptivePortalCheck];

    NSArray<id<TNLCommunicationAgentObserver>> *observers = _observers.allObjects;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        for (id<TNLCommunicationAgentObserver> observer in observers) {
            if ([observer respondsToSelector:@selector(tnl_communicationAgent:didUpdateReachabilityFromPreviousFlags:previousStatus:toCurrentFlags:currentStatus:)]) {
                [observer tnl_communicationAgent:self
          didUpdateReachabilityFromPreviousFlags:oldFlags
                                  previousStatus:oldStatus
                                  toCurrentFlags:newFlags
                                   currentStatus:newStatus];
            }
        }
    });
}

@end

@implementation TNLCommunicationAgent (Private)

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
- (void)_updateCarrier:(CTCarrier *)carrier
{
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        TNLCarrierInfoInternal *newInfo = [TNLCarrierInfoInternal carrierWithCarrier:carrier];
        TNLCarrierInfoInternal *oldInfo = self.currentCarrierInfo;
        self.currentCarrierInfo = newInfo;

        NSArray<id<TNLCommunicationAgentObserver>> *observers = self->_observers.allObjects;
        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            for (id<TNLCommunicationAgentObserver> observer in observers) {
                if ([observer respondsToSelector:@selector(tnl_communicationAgent:didUpdateCarrierFromPreviousInfo:toCurrentInfo:)]) {
                    [observer tnl_communicationAgent:self
                    didUpdateCarrierFromPreviousInfo:oldInfo
                                       toCurrentInfo:newInfo];
                }
            }
        });
    });
}
#endif // #if TARGET_OS_IOS && !TARGET_OS_MACCATALYST

- (void)private_updateRadioAccessTechnology:(NSNotification *)note
{
    NSString *newTech = note.object;
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        NSString *oldTech = self.currentWWANRadioAccessTechnology;
        if (oldTech == newTech || ([oldTech isEqualToString:newTech])) {
            return;
        }
        self.currentWWANRadioAccessTechnology = newTech;

        [self _agent_triggerCaptivePortalCheck];

        NSArray<id<TNLCommunicationAgentObserver>> *observers = self->_observers.allObjects;
        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            for (id<TNLCommunicationAgentObserver> observer in observers) {
                if ([observer respondsToSelector:@selector(tnl_communicationAgent:didUpdateWWANRadioAccessTechnologyFromPreviousTech:toCurrentTech:)]) {
                    [observer tnl_communicationAgent:self
                              didUpdateWWANRadioAccessTechnologyFromPreviousTech:oldTech
                              toCurrentTech:newTech];
                }
            }
        });
    });
}

@end

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
@implementation TNLCarrierInfoInternal

@synthesize carrierName = _carrierName;
@synthesize mobileCountryCode = _mobileCountryCode;
@synthesize mobileNetworkCode = _mobileNetworkCode;
@synthesize isoCountryCode = _isoCountryCode;
@synthesize allowsVOIP = _allowsVOIP;

+ (instancetype)carrierWithCarrier:(id<TNLCarrierInfo>)carrier
{
    if (!carrier) {
        return nil;
    }

    return [[TNLCarrierInfoInternal alloc] initWithCarrier:carrier];
}

- (instancetype)initWithCarrier:(id<TNLCarrierInfo>)carrier
{
    return [self initWithCarrierName:carrier.carrierName
                   mobileCountryCode:carrier.mobileCountryCode
                   mobileNetworkCode:carrier.mobileNetworkCode
                      isoCountryCode:carrier.isoCountryCode
                          allowsVOIP:carrier.allowsVOIP];
}

- (instancetype)initWithCarrierName:(NSString *)carrierName
                  mobileCountryCode:(NSString *)mobileCountryCode
                  mobileNetworkCode:(NSString *)mobileNetworkCode
                     isoCountryCode:(NSString *)isoCountryCode
                         allowsVOIP:(BOOL)allowsVOIP
{
    if (self = [super init]) {
        _carrierName = [carrierName copy];
        _mobileCountryCode = [mobileCountryCode copy];
        _mobileNetworkCode = [mobileNetworkCode copy];
        _isoCountryCode = [isoCountryCode copy];
        _allowsVOIP = allowsVOIP;
    }
    return self;
}

- (NSString *)description
{
    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
    if (_carrierName) {
        info[@"carrierName"] = _carrierName;
    }
    if (_mobileCountryCode) {
        info[@"mobileCountryCode"] = _mobileCountryCode;
    }
    if (_mobileNetworkCode) {
        info[@"mobileNetworkCode"] = _mobileNetworkCode;
    }
    if (_isoCountryCode) {
        info[@"isoCountryCode"] = _isoCountryCode;
    }
    info[@"allowsVOIP"] = _allowsVOIP ? @"YES" : @"NO";
    NSMutableString *description = [[NSMutableString alloc] init];
    [description appendFormat:@"<%@ %p", NSStringFromClass([self class]), self];
    [info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [description appendFormat:@", %@=%@", key, obj];
    }];
    [description appendString:@">"];
    return description;
}

@end
#endif // #if TARGET_OS_IOS && !TARGET_OS_MACCATALYST

@implementation TNLCommunicationAgent (UnsafeSynchronousAccess)

- (id<TNLCarrierInfo>)synchronousCarrierInfo
{
    if ([NSThread isMainThread]) {
        TNLLogWarning(@"Calling -[%@ %@] from main thread, which can lead to very slow XPC!", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    }

    __block id<TNLCarrierInfo> carrierInfo = nil;
    dispatch_sync(_agentQueue, ^{
        carrierInfo = self.currentCarrierInfo;
    });
    return carrierInfo;
}

@end

@implementation TNLCommunicationAgentWeakWrapper
@end

static void _ReachabilityCallback(__unused SCNetworkReachabilityRef target,
                                  const SCNetworkReachabilityFlags flags,
                                  void* info)
{
    TNLAssert(info != NULL);
    TNLAssert([(__bridge NSObject*)info isKindOfClass:[TNLCommunicationAgentWeakWrapper class]]);

    TNLCommunicationAgent *agent = [(__bridge TNLCommunicationAgentWeakWrapper *)info communicationAgent];
    if (agent) {
        [agent _agent_updateReachabilityFlags:flags status:_NetworkReachabilityStatusFromFlags(flags)];
    }
}

static TNLNetworkReachabilityStatus _NetworkReachabilityStatusFromFlags(TNLNetworkReachabilityFlags flags)
{
    if (tnl_available_ios_12) {
        const TNLNetworkReachabilityMask mask = flags;
        if (TNL_BITMASK_EXCLUDES_FLAGS(mask, TNLNetworkReachabilityMaskPathStatusSatisfied)) {
            return TNLNetworkReachabilityNotReachable;
        }

        if (TNL_BITMASK_INTERSECTS_FLAGS(mask, TNLNetworkReachabilityMaskPathIntefaceTypeWifi)) {
            return TNLNetworkReachabilityReachableViaEthernet;
        }

        if (TNL_BITMASK_INTERSECTS_FLAGS(mask, TNLNetworkReachabilityMaskPathIntefaceTypeWired)) {
            return TNLNetworkReachabilityReachableViaEthernet;
        }

        if (TNL_BITMASK_INTERSECTS_FLAGS(mask, TNLNetworkReachabilityMaskPathIntefaceTypeCellular)) {
            return TNLNetworkReachabilityReachableViaWWAN;
        }

        // "Other" happens when using VPN or other tunneling protocol.
        // On iOS/tvOS/watchOS devices: WiFi or Wired or Cellular would have been hit above.
        // On Mac and iOS Simulator: WiFi or Wired will _NOT_ be provide in the flags so, even though we coerce to WiFi in this case on Mac, presume Ethernet if we get here.
        if (TNL_BITMASK_INTERSECTS_FLAGS(mask, TNLNetworkReachabilityMaskPathIntefaceTypeOther)) {
            return TNLNetworkReachabilityReachableViaEthernet;
        }

        return TNLNetworkReachabilityUndetermined;
    }

    if (TNL_BITMASK_EXCLUDES_FLAGS(flags, kSCNetworkReachabilityFlagsReachable)) {
        return TNLNetworkReachabilityNotReachable;
    }

#if TARGET_OS_IOS
    if (TNL_BITMASK_INTERSECTS_FLAGS(flags, kSCNetworkReachabilityFlagsIsWWAN)) {
        return TNLNetworkReachabilityReachableViaWWAN;
    }
#endif

    if (TNL_BITMASK_EXCLUDES_FLAGS(flags, kSCNetworkReachabilityFlagsConnectionRequired)) {
        return TNLNetworkReachabilityReachableViaEthernet;
    }

    if (TNL_BITMASK_EXCLUDES_FLAGS(flags, kSCNetworkReachabilityFlagsInterventionRequired)) {
        if (TNL_BITMASK_INTERSECTS_FLAGS(flags, kSCNetworkReachabilityFlagsConnectionOnDemand)) {
            return TNLNetworkReachabilityReachableViaEthernet;
        }
        if (TNL_BITMASK_INTERSECTS_FLAGS(flags, kSCNetworkReachabilityFlagsConnectionOnTraffic)) {
            return TNLNetworkReachabilityReachableViaEthernet;
        }
    }

    return TNLNetworkReachabilityNotReachable;
}

static TNLNetworkReachabilityFlags _NetworkReachabilityFlagsFromPath(nw_path_t path)
{
    if (tnl_available_ios_12) {
        TNLNetworkReachabilityMask flags = 0;
        if (path != nil) {
            const nw_path_status_t status = nw_path_get_status(path);
            if (status > 0) {
#if DEBUG
                if (gTwitterNetworkLayerAssertEnabled) {
                    switch (status) {
                        case nw_path_status_invalid:
                        case nw_path_status_satisfied:
                        case nw_path_status_unsatisfied:
                        case nw_path_status_satisfiable:
                            break;
                        default:
                            TNLAssertMessage(0, @"the nw_path_status_t enum has expanded!  Need to update TNLNetworkReachabilityMask.");
                            break;
                    }
                }
#endif
                flags |= _NWPathStatusToFlag(status);
            }

            for (nw_interface_type_t itype = 0; itype <= 4; itype++) {
                const bool usesInterface = nw_path_uses_interface_type(path, itype);
                if (usesInterface) {
                    flags |= _NWInterfaceTypeToFlag(itype);
                }
            }

#if TARGET_OS_SIMULATOR || TARGET_OS_MACCATALYST || TARGET_OS_OSX
            // When run on macOS (however the avenue) we will coerce
            // to have an ethernet connection when we detect `Other` but no actual interface.
            // This is most commonly due to VPN connections "hiding" the physical interface on Macs.
            if (TNL_BITMASK_INTERSECTS_FLAGS(flags, TNLNetworkReachabilityMaskPathIntefaceTypeOther)) {
                if (TNL_BITMASK_EXCLUDES_FLAGS(flags, TNLNetworkReachabilityMaskPathIntefaceTypeWifi | TNLNetworkReachabilityMaskPathIntefaceTypeCellular | TNLNetworkReachabilityMaskPathIntefaceTypeWired)) {
                    flags |= TNLNetworkReachabilityMaskPathIntefaceTypeWifi;
                }
            }
#endif

            if (tnl_available_ios_13) {
                if (nw_path_is_expensive(path)) {
                    flags |= TNLNetworkReachabilityMaskPathConditionExpensive;
                }
                if (nw_path_is_constrained(path)) {
                    flags |= TNLNetworkReachabilityMaskPathConditionConstrained;
                }
            }
        }
        return flags;
    }

    return 0;
}

TNLWWANRadioAccessTechnologyValue TNLWWANRadioAccessTechnologyValueFromString(NSString *WWANTechString)
{
    static NSDictionary* sTechStringToValueMap = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
        sTechStringToValueMap = @{
                                  CTRadioAccessTechnologyGPRS : @(TNLWWANRadioAccessTechnologyValueGPRS),
                                  CTRadioAccessTechnologyEdge: @(TNLWWANRadioAccessTechnologyValueEDGE),
                                  CTRadioAccessTechnologyWCDMA: @(TNLWWANRadioAccessTechnologyValueUMTS),
                                  CTRadioAccessTechnologyHSDPA: @(TNLWWANRadioAccessTechnologyValueHSDPA),
                                  CTRadioAccessTechnologyHSUPA: @(TNLWWANRadioAccessTechnologyValueHSUPA),
                                  CTRadioAccessTechnologyCDMA1x: @(TNLWWANRadioAccessTechnologyValue1xRTT),
                                  CTRadioAccessTechnologyCDMAEVDORev0: @(TNLWWANRadioAccessTechnologyValueEVDO_0),
                                  CTRadioAccessTechnologyCDMAEVDORevA: @(TNLWWANRadioAccessTechnologyValueEVDO_A),
                                  CTRadioAccessTechnologyCDMAEVDORevB: @(TNLWWANRadioAccessTechnologyValueEVDO_B),
                                  CTRadioAccessTechnologyeHRPD: @(TNLWWANRadioAccessTechnologyValueEHRPD),
                                  CTRadioAccessTechnologyLTE: @(TNLWWANRadioAccessTechnologyValueLTE)
                                  };
#else
        sTechStringToValueMap = @{};
#endif
    });

    NSNumber *valueNumber = (WWANTechString) ? sTechStringToValueMap[WWANTechString] : nil;
    return (valueNumber) ? [valueNumber integerValue] : TNLWWANRadioAccessTechnologyValueUnknown;
}

NSString *TNLWWANRadioAccessTechnologyValueToString(TNLWWANRadioAccessTechnologyValue value)
{
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    switch (value) {
        case TNLWWANRadioAccessTechnologyValueGPRS:
            return CTRadioAccessTechnologyGPRS;
        case TNLWWANRadioAccessTechnologyValueEDGE:
            return CTRadioAccessTechnologyEdge;
        case TNLWWANRadioAccessTechnologyValueUMTS:
            return CTRadioAccessTechnologyWCDMA;
        case TNLWWANRadioAccessTechnologyValueHSDPA:
            return CTRadioAccessTechnologyHSDPA;
        case TNLWWANRadioAccessTechnologyValueHSUPA:
            return CTRadioAccessTechnologyHSUPA;
        case TNLWWANRadioAccessTechnologyValueEVDO_0:
            return CTRadioAccessTechnologyCDMAEVDORev0;
        case TNLWWANRadioAccessTechnologyValueEVDO_A:
            return CTRadioAccessTechnologyCDMAEVDORevA;
        case TNLWWANRadioAccessTechnologyValueEVDO_B:
            return CTRadioAccessTechnologyCDMAEVDORevB;
        case TNLWWANRadioAccessTechnologyValue1xRTT:
            return CTRadioAccessTechnologyCDMA1x;
        case TNLWWANRadioAccessTechnologyValueLTE:
            return CTRadioAccessTechnologyLTE;
        case TNLWWANRadioAccessTechnologyValueEHRPD:
            return CTRadioAccessTechnologyeHRPD;
        case TNLWWANRadioAccessTechnologyValueHSPA:
        case TNLWWANRadioAccessTechnologyValueCDMA:
        case TNLWWANRadioAccessTechnologyValueIDEN:
        case TNLWWANRadioAccessTechnologyValueHSPAP:
        case TNLWWANRadioAccessTechnologyValueUnknown:
            break;
    }
#endif // TARGET_OS_IOS && !TARGET_OS_MACCATALYST

    return @"unknown";
}

TNLWWANRadioAccessGeneration TNLWWANRadioAccessGenerationForTechnologyValue(TNLWWANRadioAccessTechnologyValue value)
{
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    switch (value) {
        case TNLWWANRadioAccessTechnologyValueEVDO_0:
        case TNLWWANRadioAccessTechnologyValue1xRTT:
            return TNLWWANRadioAccessGeneration1G;
        case TNLWWANRadioAccessTechnologyValueGPRS:
        case TNLWWANRadioAccessTechnologyValueEDGE:
        case TNLWWANRadioAccessTechnologyValueIDEN:
        case TNLWWANRadioAccessTechnologyValueCDMA:
            return TNLWWANRadioAccessGeneration2G;
        case TNLWWANRadioAccessTechnologyValueUMTS:
        case TNLWWANRadioAccessTechnologyValueHSDPA:
        case TNLWWANRadioAccessTechnologyValueHSUPA:
        case TNLWWANRadioAccessTechnologyValueHSPA:
        case TNLWWANRadioAccessTechnologyValueEVDO_A:
        case TNLWWANRadioAccessTechnologyValueEVDO_B:
            return TNLWWANRadioAccessGeneration3G;
        case TNLWWANRadioAccessTechnologyValueLTE:
        case TNLWWANRadioAccessTechnologyValueEHRPD:
        case TNLWWANRadioAccessTechnologyValueHSPAP:
            return TNLWWANRadioAccessGeneration4G;
        case TNLWWANRadioAccessTechnologyValueUnknown:
            break;
    }
#endif // #if TARGET_OS_IOS && !TARGET_OS_MACCATALYST

    return TNLWWANRadioAccessGenerationUnknown;
}

NSString *TNLNetworkReachabilityStatusToString(TNLNetworkReachabilityStatus status)
{
    switch (status) {
        case TNLNetworkReachabilityNotReachable:
            return @"unreachable";
        case TNLNetworkReachabilityReachableViaEthernet:
            return @"wifi";
        case TNLNetworkReachabilityReachableViaWWAN:
            return @"wwan";
        case TNLNetworkReachabilityUndetermined:
            break;
    }

    return @"undetermined";
}

NSString *TNLCaptivePortalStatusToString(TNLCaptivePortalStatus status)
{
    switch (status) {
        case TNLCaptivePortalStatusUndetermined:
            break;
        case TNLCaptivePortalStatusNoCaptivePortal:
            return @"not_captive";
        case TNLCaptivePortalStatusCaptivePortalDetected:
            return @"captive";
        case TNLCaptivePortalStatusDetectionBlockedByAppTransportSecurity:
            return @"ats_blocked";
    }

    return @"undetermined";
}

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST

NSDictionary * __nullable TNLCarrierInfoToDictionary(id<TNLCarrierInfo> __nullable carrierInfo)
{
    if (!carrierInfo) {
        return nil;
    }

    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    if (carrierInfo.carrierName) {
        dict[@"carrierName"] = carrierInfo.carrierName;
    }
    if (carrierInfo.mobileNetworkCode) {
        dict[@"mobileNetworkCode"] = carrierInfo.mobileNetworkCode;
    }
    if (carrierInfo.mobileCountryCode) {
        dict[@"mobileCountryCode"] = carrierInfo.mobileCountryCode;
    }
    if (carrierInfo.isoCountryCode) {
        dict[@"isoCountryCode"] = carrierInfo.isoCountryCode;
    }
    dict[@"allowsVOIP"] = @(carrierInfo.allowsVOIP);
    return [dict copy];
}

id<TNLCarrierInfo> __nullable TNLCarrierInfoFromDictionary(NSDictionary * __nullable dict)
{
    if (!dict.count) {
        return nil;
    }

    return [[TNLCarrierInfoInternal alloc] initWithCarrierName:dict[@"carrierName"]
                                             mobileCountryCode:dict[@"mobileNetworkCode"]
                                             mobileNetworkCode:dict[@"mobileCountryCode"]
                                                isoCountryCode:dict[@"isoCountryCode"]
                                                    allowsVOIP:[dict[@"allowsVOIP"] boolValue]];
}

#endif // #if TARGET_OS_IOS && !TARGET_OS_MACCATALYST

NS_INLINE const char _DebugCharFromReachabilityFlag(TNLNetworkReachabilityFlags flags, uint32_t flag, const char presentChar)
{
    return TNL_BITMASK_HAS_SUBSET_FLAGS(flags, flag) ? presentChar : '_';
}

NSString *TNLDebugStringFromNetworkReachabilityFlags(TNLNetworkReachabilityFlags flags)
{
    if (tnl_available_ios_12) {
        NSString *dbgStr;
        dbgStr = [NSString stringWithFormat:@"%c%c%c%c%c%c%c%c",
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathStatusUnsatisfied, 'U'),
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathStatusSatisfied, 'S'),
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathStatusSatisfiable, 's'),
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathIntefaceTypeOther, 'o'),
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathIntefaceTypeWifi, 'w'),
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathIntefaceTypeCellular, 'c'),
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathIntefaceTypeWired, 'e'),
                  _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathIntefaceTypeLoopback, 'l')
                ];
        if (tnl_available_ios_13) {
            dbgStr = [dbgStr stringByAppendingFormat:@"%c%c",
                      _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathConditionExpensive, '$'),
                      _DebugCharFromReachabilityFlag(flags, TNLNetworkReachabilityMaskPathConditionConstrained, 'C')];
        }
        return dbgStr;
    }

    return [NSString stringWithFormat:
#if TARGET_OS_IOS
            @"%c%c%c%c%c%c%c%c%c",
#else
            @"%c%c%c%c%c%c%c%c",
#endif
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsTransientConnection, 'T'),
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsReachable, 'R'),
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsConnectionRequired, 'r'),
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsConnectionOnTraffic, 't'),
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsInterventionRequired, 'i'),
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsConnectionOnDemand, 'd'),
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsIsLocalAddress, 'L'),
            _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsIsDirect, 'D')
#if TARGET_OS_IOS
            , _DebugCharFromReachabilityFlag(flags, kSCNetworkReachabilityFlagsIsWWAN, 'W')
#endif
            ];
}

NSDictionary<NSString *, id> *TNLCarrierInfoToDictionaryDescription(id<TNLCarrierInfo> carrierInfo)
{
    return @{
        @"carrierName" : carrierInfo.carrierName ?: [NSNull null],
        @"mobileCountryCode" : carrierInfo.mobileCountryCode ?: [NSNull null],
        @"mobileNetworkCode" : carrierInfo.mobileNetworkCode ?: [NSNull null],
        @"isoCountryCode" : carrierInfo.isoCountryCode ?: [NSNull null],
        @"allowsVOIP" : @(carrierInfo.allowsVOIP)
    };
}

#import <ifaddrs.h>

static BOOL _HasCellularInterface()
{
    struct ifaddrs * addrs;
    if (getifaddrs(&addrs) != 0) {
        return NO;
    }

    tnl_defer(^{
        freeifaddrs(addrs);
    });

    for (const struct ifaddrs * cursor = addrs; cursor != NULL; cursor = cursor->ifa_next) {
        NSString *name = @(cursor->ifa_name);
        if ([name isEqualToString:@"pdp_ip0"]) {
            // All cellular interfaces are `pdp_ip`.
            // There can be multiple, but the first one will always be number `0`.
            return YES;
        }
    }

    return NO;
}

#endif // !TARGET_OS_WATCH

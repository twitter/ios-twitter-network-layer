//
//  TNLCommunicationAgent.m
//  TwitterNetworkLayer
//
//  Created on 5/2/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLCommunicationAgent_Project.h"

#define SELF_ARG PRIVATE_SELF(TNLCommunicationAgent)

static void _ReachabilityCallback(__unused SCNetworkReachabilityRef target,
                                  const SCNetworkReachabilityFlags flags,
                                  void* info);
static TNLNetworkReachabilityStatus _NetworkReachabilityStatusFromFlags(SCNetworkReachabilityFlags flags) __attribute__((const));

@interface TNLCommunicationAgentWeakWrapper : NSObject
@property (nonatomic, weak) TNLCommunicationAgent *communicationAgent;
@end

@interface TNLCommunicationAgent ()

@property (atomic) TNLNetworkReachabilityStatus currentReachabilityStatus;
@property (atomic) SCNetworkReachabilityFlags currentReachabilityFlags;
@property (atomic, copy, nullable) NSString *currentWWANRadioAccessTechnology;
@property (atomic, nullable) id<TNLCarrierInfo> currentCarrierInfo;

@end

@interface TNLCommunicationAgent (Agent)

static void _agent_initialize(SELF_ARG);
static void _agent_forciblyUpdateReachability(SELF_ARG);
static void _agent_updateReachabilityFlags(SELF_ARG,
                                           SCNetworkReachabilityFlags newFlags);

static void _agent_addObserver(SELF_ARG,
                               id<TNLCommunicationAgentObserver> observer);
static void _agent_removeObserver(SELF_ARG,
                                  id<TNLCommunicationAgentObserver> observer);

static void _agent_identifyReachability(SELF_ARG,
                                        TNLCommunicationAgentIdentifyReachabilityCallback callback);
static void _agent_identifyCarrierInfo(SELF_ARG,
                                       TNLCommunicationAgentIdentifyCarrierInfoCallback callback);
static void _agent_identifyWWANRadioAccessTechnology(SELF_ARG,
                                                     TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback callback);

@end

@interface TNLCommunicationAgent (Private)
#if TARGET_OS_IOS
static void _updateCarrier(SELF_ARG,
                           CTCarrier *carrier);
#endif
- (void)private_updateRadioAccessTechnology:(NSNotification *)note;
@end

@implementation TNLCommunicationAgent
{
    NSMutableArray<id<TNLCommunicationAgentObserver>> *_queuedObservers;
    NSMutableArray<TNLCommunicationAgentIdentifyReachabilityCallback> *_queuedReachabilityCallbacks;
    NSMutableArray<TNLCommunicationAgentIdentifyCarrierInfoCallback> *_queuedCarrierInfoCallbacks;
    NSMutableArray<TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback> *_queuedRadioTechInfoCallbacks;

    NSHashTable<id<TNLCommunicationAgentObserver>> *_observers;

    dispatch_queue_t _agentQueue;
    NSOperationQueue *_agentOperationQueue;
    TNLCommunicationAgentWeakWrapper *_agentWrapper;

    SCNetworkReachabilityRef _reachabilityRef;
#if TARGET_OS_IOS
    CTTelephonyNetworkInfo *_internalTelephonyNetworkInfo;
#endif
    struct {
        BOOL initialized:1;
        BOOL initializedReachability:1;
        BOOL initializedCarrier:1;
        BOOL initializedRadioTech:1;
    } _flags;
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
        _agentQueue = dispatch_queue_create("TNLCommunicationAgent.queue", DISPATCH_QUEUE_SERIAL);
        _agentOperationQueue = [[NSOperationQueue alloc] init];
        _agentOperationQueue.name = @"TNLCommunicationAgent.queue";
        _agentOperationQueue.maxConcurrentOperationCount = 1;
        _agentOperationQueue.underlyingQueue = _agentQueue;
        if ([_agentOperationQueue respondsToSelector:@selector(setQualityOfService:)]) {
            _agentOperationQueue.qualityOfService = NSQualityOfServiceUtility;
        }
        _agentWrapper = [[TNLCommunicationAgentWeakWrapper alloc] init];
        _agentWrapper.communicationAgent = self;

        tnl_dispatch_async_autoreleasing(_agentQueue, ^{
            _agent_initialize(self);
        });
    }

    return self;
}

- (void)dealloc
{
    if (_reachabilityRef) {
        SCNetworkReachabilitySetCallback(_reachabilityRef, NULL, NULL);
        SCNetworkReachabilitySetDispatchQueue(_reachabilityRef, NULL);
        CFRelease(_reachabilityRef);
    }

#if TARGET_OS_IOS
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
        dispatch_async(agentQueue, ^{
            weakWrapper.communicationAgent = nil;
        });
    });
}

- (void)addObserver:(id<TNLCommunicationAgentObserver>)observer
{
    dispatch_async(_agentQueue, ^{
        _agent_addObserver(self, observer);
    });
}

- (void)removeObserver:(id<TNLCommunicationAgentObserver>)observer
{
    dispatch_async(_agentQueue, ^{
        _agent_removeObserver(self, observer);
    });
}

- (void)identifyReachability:(TNLCommunicationAgentIdentifyReachabilityCallback)callback
{
    dispatch_async(_agentQueue, ^{
        _agent_identifyReachability(self, callback);
    });
}

- (void)identifyCarrierInfo:(TNLCommunicationAgentIdentifyCarrierInfoCallback)callback
{
    dispatch_async(_agentQueue, ^{
        _agent_identifyCarrierInfo(self, callback);
    });
}

- (void)identifyWWANRadioAccessTechnology:(TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback)callback
{
    dispatch_async(_agentQueue, ^{
        _agent_identifyWWANRadioAccessTechnology(self, callback);
    });
}

@end

@implementation TNLCommunicationAgent (Agent)

static void _agent_forciblyUpdateReachability(SELF_ARG)
{
    if (!self) {
        return;
    }

    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(self->_reachabilityRef, &flags)) {
        self.currentReachabilityFlags = flags;
        self.currentReachabilityStatus = _NetworkReachabilityStatusFromFlags(flags);
    } else {
        self.currentReachabilityFlags = 0;
        self.currentReachabilityStatus = TNLNetworkReachabilityUndetermined;
    }
}

static void _agent_initializeReachability(SELF_ARG)
{
    if (!self) {
        return;
    }

    self->_reachabilityRef = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, self.host.UTF8String);

    _agent_forciblyUpdateReachability(self);

    SCNetworkReachabilityContext context = { 0, (__bridge void*)self->_agentWrapper, NULL, NULL, NULL };
    if (SCNetworkReachabilitySetCallback(self->_reachabilityRef, _ReachabilityCallback, &context)) {
        if (SCNetworkReachabilitySetDispatchQueue(self->_reachabilityRef, self->_agentQueue)) {
            self->_flags.initializedReachability = 1;
        } else {
            SCNetworkReachabilitySetCallback(self->_reachabilityRef, NULL, NULL);
            CFRelease(self->_reachabilityRef);
            self->_reachabilityRef = NULL;
        }
    }

    if (!self->_flags.initializedReachability) {
        TNLLogError(@"Failed to start reachability: %@", self.host);
        if (self->_reachabilityRef) {
            CFRelease(self->_reachabilityRef);
            self->_reachabilityRef = NULL;
        }
    }
}

static void _agent_initializeTelephony(SELF_ARG)
{
    if (!self) {
        return;
    }

#if TARGET_OS_IOS
    __weak typeof(self) weakSelf = self;

    self->_internalTelephonyNetworkInfo = [[CTTelephonyNetworkInfo alloc] init];
    self->_internalTelephonyNetworkInfo.subscriberCellularProviderDidUpdateNotifier = ^(CTCarrier *carrier) {
        _updateCarrier(weakSelf, carrier);
    };
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(private_updateRadioAccessTechnology:)
                                                 name:CTRadioAccessTechnologyDidChangeNotification object:nil];
    self.currentCarrierInfo = [TNLCarrierInfoInternal carrierWithCarrier:self->_internalTelephonyNetworkInfo.subscriberCellularProvider];
    self.currentWWANRadioAccessTechnology = [self->_internalTelephonyNetworkInfo.currentRadioAccessTechnology copy];
#endif

    self->_flags.initializedCarrier = 1;
    self->_flags.initializedRadioTech = 1;
}

static void _agent_initialize(SELF_ARG)
{
    if (!self) {
        return;
    }

    TNLAssert(!self->_flags.initialized);
    TNLAssert(!self->_flags.initializedReachability);
    TNLAssert(!self->_flags.initializedCarrier);
    TNLAssert(!self->_flags.initializedRadioTech);
    TNLAssert(!self->_reachabilityRef);

    _agent_initializeReachability(self);
    _agent_initializeTelephony(self);

    NSArray<id<TNLCommunicationAgentObserver>> *queuedObservers = [self->_queuedObservers copy];
    NSArray<TNLCommunicationAgentIdentifyReachabilityCallback> *reachBlocks = [self->_queuedReachabilityCallbacks copy];
    NSArray<TNLCommunicationAgentIdentifyCarrierInfoCallback> *carrierBlocks = [self->_queuedCarrierInfoCallbacks copy];
    NSArray<TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback> *radioBlocks = [self->_queuedRadioTechInfoCallbacks copy];

    self->_queuedObservers = nil;
    self->_queuedReachabilityCallbacks = nil;
    self->_queuedCarrierInfoCallbacks = nil;
    self->_queuedRadioTechInfoCallbacks = nil;

    self->_flags.initialized = 1;

    for (id<TNLCommunicationAgentObserver> observer in queuedObservers) {
        _agent_addObserver(self, observer);
    }
    for (TNLCommunicationAgentIdentifyReachabilityCallback block in reachBlocks) {
        _agent_identifyReachability(self, block);
    }
    for (TNLCommunicationAgentIdentifyCarrierInfoCallback block in carrierBlocks) {
        _agent_identifyCarrierInfo(self, block);
    }
    for (TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback block in radioBlocks) {
        _agent_identifyWWANRadioAccessTechnology(self, block);
    }
}

static void _agent_addObserver(SELF_ARG,
                               id<TNLCommunicationAgentObserver> observer)
{
    if (!self) {
        return;
    }

    if (!self->_flags.initialized) {
        [self->_queuedObservers addObject:observer];
        return;
    }

    [self->_observers addObject:observer];

    if ([observer respondsToSelector:@selector(tnl_communicationAgent:didRegisterObserverWithInitialReachabilityFlags:status:carrierInfo:WWANRadioAccessTechnology:)]) {
        SCNetworkReachabilityFlags flags = self.currentReachabilityFlags;
        TNLNetworkReachabilityStatus status = self.currentReachabilityStatus;
        id<TNLCarrierInfo> info = self.currentCarrierInfo;
        NSString *radioTech = self.currentWWANRadioAccessTechnology;
        tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
            [observer tnl_communicationAgent:self
                      didRegisterObserverWithInitialReachabilityFlags:flags
                      status:status
                      carrierInfo:info
                      WWANRadioAccessTechnology:radioTech];
        });
    }
}

static void _agent_removeObserver(SELF_ARG,
                                  id<TNLCommunicationAgentObserver> observer)
{
    if (!self) {
        return;
    }

    if (!self->_flags.initialized) {
        [self->_queuedObservers removeObject:observer];
        return;
    }

    [self->_observers removeObject:observer];
}

static void _agent_identifyReachability(SELF_ARG,
                                        TNLCommunicationAgentIdentifyReachabilityCallback callback)
{
    if (!self) {
        return;
    }

    if (!self->_flags.initialized) {
        [self->_queuedReachabilityCallbacks addObject:[callback copy]];
        return;
    }

    SCNetworkReachabilityFlags flags = self.currentReachabilityFlags;
    TNLNetworkReachabilityStatus status = self.currentReachabilityStatus;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        callback(flags, status);
    });
}

static void _agent_identifyCarrierInfo(SELF_ARG,
                                       TNLCommunicationAgentIdentifyCarrierInfoCallback callback)
{
    if (!self) {
        return;
    }

    if (!self->_flags.initialized) {
        [self->_queuedCarrierInfoCallbacks addObject:[callback copy]];
        return;
    }

    id<TNLCarrierInfo> info = self.currentCarrierInfo;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        callback(info);
    });
}

static void _agent_identifyWWANRadioAccessTechnology(SELF_ARG,
                                                     TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback callback)
{
    if (!self) {
        return;
    }

    if (!self->_flags.initialized) {
        [self->_queuedRadioTechInfoCallbacks addObject:[callback copy]];
        return;
    }

    NSString *radioTech = self.currentWWANRadioAccessTechnology;
    tnl_dispatch_async_autoreleasing(dispatch_get_main_queue(), ^{
        callback(radioTech);
    });
}

static void _agent_updateReachabilityFlags(SELF_ARG,
                                           SCNetworkReachabilityFlags newFlags)
{
    if (!self) {
        return;
    }

    const SCNetworkReachabilityFlags oldFlags = self.currentReachabilityFlags;
    const TNLNetworkReachabilityStatus oldStatus = self.currentReachabilityStatus;

    if (oldFlags == newFlags && oldStatus != TNLNetworkReachabilityUndetermined) {
        return;
    }

    const TNLNetworkReachabilityStatus newStatus = _NetworkReachabilityStatusFromFlags(newFlags);

    self.currentReachabilityStatus = newStatus;
    self.currentReachabilityFlags = newFlags;

    NSArray<id<TNLCommunicationAgentObserver>> *observers = self->_observers.allObjects;
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

#if TARGET_OS_IOS
static void _updateCarrier(SELF_ARG,
                           CTCarrier *carrier)
{
    if (!self) {
        return;
    }

    tnl_dispatch_async_autoreleasing(self->_agentQueue, ^{
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
#endif

- (void)private_updateRadioAccessTechnology:(NSNotification *)note
{
    NSString *newTech = note.object;
    tnl_dispatch_async_autoreleasing(_agentQueue, ^{
        NSString *oldTech = self.currentWWANRadioAccessTechnology;
        if (oldTech == newTech || ([oldTech isEqualToString:newTech])) {
            return;
        }
        self.currentWWANRadioAccessTechnology = newTech;

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

#if TARGET_OS_IOS
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
#endif

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
        _agent_updateReachabilityFlags(agent, flags);
    }
}

static TNLNetworkReachabilityStatus _NetworkReachabilityStatusFromFlags(SCNetworkReachabilityFlags flags)
{
    if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
        return TNLNetworkReachabilityNotReachable;
    }

#if TARGET_OS_IOS
    if((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
        return TNLNetworkReachabilityReachableViaWWAN;
    }
#endif

    if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
        return TNLNetworkReachabilityReachableViaWiFi;
    }

    if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
        if ((flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0) {
            return TNLNetworkReachabilityReachableViaWiFi;
        }
        if ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0) {
            return TNLNetworkReachabilityReachableViaWiFi;
        }
    }

    return TNLNetworkReachabilityNotReachable;
}

TNLWWANRadioAccessTechnologyValue TNLWWANRadioAccessTechnologyValueFromString(NSString *WWANTechString)
{
    static NSDictionary* sTechStringToValueMap = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_IOS
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
    switch (value) {
#if TARGET_OS_IOS
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
#else
        case TNLWWANRadioAccessTechnologyValueGPRS:
        case TNLWWANRadioAccessTechnologyValueEDGE:
        case TNLWWANRadioAccessTechnologyValueUMTS:
        case TNLWWANRadioAccessTechnologyValueHSDPA:
        case TNLWWANRadioAccessTechnologyValueHSUPA:
        case TNLWWANRadioAccessTechnologyValueEVDO_0:
        case TNLWWANRadioAccessTechnologyValueEVDO_A:
        case TNLWWANRadioAccessTechnologyValueEVDO_B:
        case TNLWWANRadioAccessTechnologyValue1xRTT:
        case TNLWWANRadioAccessTechnologyValueLTE:
        case TNLWWANRadioAccessTechnologyValueEHRPD:
#endif
        case TNLWWANRadioAccessTechnologyValueHSPA:
        case TNLWWANRadioAccessTechnologyValueCDMA:
        case TNLWWANRadioAccessTechnologyValueIDEN:
        case TNLWWANRadioAccessTechnologyValueHSPAP:
        case TNLWWANRadioAccessTechnologyValueUnknown:
            break;
    }

    return @"unknown";
}

TNLWWANRadioAccessGeneration TNLWWANRadioAccessGenerationForTechnologyValue(TNLWWANRadioAccessTechnologyValue value)
{
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

    return TNLWWANRadioAccessGenerationUnknown;
}

NSString *TNLNetworkReachabilityStatusToString(TNLNetworkReachabilityStatus status)
{
    switch (status) {
        case TNLNetworkReachabilityNotReachable:
            return @"unreachable";
        case TNLNetworkReachabilityReachableViaWiFi:
            return @"wifi";
        case TNLNetworkReachabilityReachableViaWWAN:
            return @"wwan";
        case TNLNetworkReachabilityUndetermined:
            break;
    }

    return @"undetermined";
}

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

NS_INLINE const char _DebugCharFromReachabilityFlag(SCNetworkReachabilityFlags flags, uint32_t flag, const char presentChar)
{
    return TNL_BITMASK_HAS_SUBSET_FLAGS(flags, flag) ? presentChar : '_';
}

NSString *TNLDebugStringFromNetworkReachabilityFlags(SCNetworkReachabilityFlags flags)
{
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

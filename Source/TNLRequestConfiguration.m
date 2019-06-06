//
//  TNLRequestConfiguration.m
//  TwitterNetworkLayer
//
//  Created on 7/15/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#include <objc/message.h>

#import "NSHTTPCookieStorage+TNLAdditions.h"
#import "NSURLCache+TNLAdditions.h"
#import "NSURLCredentialStorage+TNLAdditions.h"
#import "NSURLSessionConfiguration+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLParameterCollection.h"
#import "TNLPseudoURLProtocol.h"
#import "TNLRequestConfiguration_Project.h"
#import "TNLURLSessionManager.h"

NS_ASSUME_NONNULL_BEGIN

static const char kAssociatedConfigKey[] = "tnl.associated.config";

typedef struct {
    const NSTimeInterval idleTimeout;
    const NSTimeInterval attemptTimeout;
    const NSTimeInterval operationTimeout;
} TNLRequestAnatomyTimeouts;

static const TNLRequestAnatomyTimeouts kAnatomyTimeouts[] = {
    // TNLRequestAnatomySmallRequestSmallResponse
    { .idleTimeout = 30, .attemptTimeout = 30, .operationTimeout = 90 },

    // TNLRequestAnatomySmallRequestLargeResponse (default)
    { .idleTimeout = 30, .attemptTimeout = 60, .operationTimeout = 180 },

    // TNLRequestAnatomyLargeRequestSmallResponse
    { .idleTimeout = 30, .attemptTimeout = 60, .operationTimeout = 180 },

    // TNLRequestAnatomyLargeRequestLargeResponse
    { .idleTimeout = 30, .attemptTimeout = 120, .operationTimeout = 360 },

    // TNLRequestAnatomyVeryLargeRequestSmallResponse
    { .idleTimeout = 30, .attemptTimeout = 240, .operationTimeout = 480 },

    // TNLRequestAnatomySmallRequestVeryLargeResponse
    { .idleTimeout = 30, .attemptTimeout = 180, .operationTimeout = 480 },

    // TNLRequestAnatomySmallRequestStreamingResponse
    { .idleTimeout = 30, .attemptTimeout = NSTimeIntervalSince1970, .operationTimeout = NSTimeIntervalSince1970 },
};

static const NSInteger kMaxAnatomyTimeouts = TNLRequestAnatomySmallRequestStreamingResponse + 1;

TNLStaticAssert((sizeof(kAnatomyTimeouts) / sizeof(kAnatomyTimeouts[0])) == kMaxAnatomyTimeouts, ANATOMY_TIMEOUT_COUNT_MISSMATCH);

#define kConfigurationIdleTimeoutDefault (kAnatomyTimeouts[TNLRequestAnatomyDefault].idleTimeout)
#define kConfigurationAttemptTimeoutDefault (kAnatomyTimeouts[TNLRequestAnatomyDefault].attemptTimeout) // Apple's default is 7 days (biasing towards background sessions).  We'll bias towards foreground sessions.
#define kConfigurationOperationTimeoutDefault (kAnatomyTimeouts[TNLRequestAnatomyDefault].operationTimeout)
static const NSTimeInterval kConfigurationDeferrableIntervalDefault = 0.0;

@interface TNLRequestConfiguration ()

- (instancetype)initWithConfiguration:(nullable TNLRequestConfiguration *)config;
- (instancetype)initWithIdleTimeout:(NSTimeInterval)idleTimeout
                     attemptTimeout:(NSTimeInterval)attemptTimeout
                   operationTimeout:(NSTimeInterval)operationTimeout;

@end

@implementation TNLRequestConfiguration

#pragma mark @synthesize

@synthesize retryPolicyProvider = _retryPolicyProvider;
@synthesize contentEncoder = _contentEncoder;
@synthesize additionalContentDecoders = _additionalContentDecoders;
@synthesize URLCredentialStorage = _URLCredentialStorage;
@synthesize URLCache = _URLCache;
@synthesize sharedContainerIdentifier = _sharedContainerIdentifier;
@synthesize cookieStorage = _cookieStorage;

#pragma mark properties

- (TNLRequestExecutionMode)executionMode
{
    return _ivars.executionMode;
}

- (TNLRequestRedirectPolicy)redirectPolicy
{
    return _ivars.redirectPolicy;
}

- (TNLResponseDataConsumptionMode)responseDataConsumptionMode
{
    return _ivars.responseDataConsumptionMode;
}

- (TNLRequestProtocolOptions)protocolOptions
{
    return _ivars.protocolOptions;
}

- (TNLRequestConnectivityOptions)connectivityOptions
{
    return _ivars.connectivityOptions;
}

- (BOOL)contributeToExecutingNetworkConnectionsCount
{
    return _ivars.contributeToExecutingNetworkConnectionsCount;
}

- (BOOL)skipHostSanitization
{
    return _ivars.skipHostSanitization;
}

- (TNLResponseHashComputeAlgorithm)responseComputeHashAlgorithm
{
    return _ivars.responseComputeHashAlgorithm;
}

- (NSTimeInterval)idleTimeout
{
    return _ivars.idleTimeout;
}

- (NSTimeInterval)attemptTimeout
{
    return _ivars.attemptTimeout;
}

- (NSTimeInterval)operationTimeout
{
    return _ivars.operationTimeout;
}

- (NSTimeInterval)deferrableInterval
{
    return _ivars.deferrableInterval;
}

- (NSURLRequestCachePolicy)cachePolicy
{
    return _ivars.cachePolicy;
}

- (NSURLRequestNetworkServiceType)networkServiceType
{
    return _ivars.networkServiceType;
}

- (NSHTTPCookieAcceptPolicy)cookieAcceptPolicy
{
    return _ivars.cookieAcceptPolicy;
}

- (BOOL)shouldSetCookies
{
    return _ivars.shouldSetCookies;
}

- (BOOL)allowsCellularAccess
{
    return _ivars.allowsCellularAccess;
}

- (BOOL)isDiscretionary
{
    return _ivars.discretionary;
}

- (BOOL)shouldLaunchAppForBackgroundEvents
{
    return _ivars.shouldLaunchAppForBackgroundEvents;
}

- (NSURLSessionMultipathServiceType)multipathServiceType
{
#if TARGET_OS_IOS
    if (tnl_available_ios_11) {
        return _ivars.multipathServiceType;
    }
#endif
    return 0;
}

#pragma mark Constructors

+ (instancetype)defaultConfiguration
{
    return [[[self class] alloc] init];
}

+ (instancetype)configurationWithExpectedAnatomy:(TNLRequestAnatomy)anatomy
{
    if (anatomy >= kMaxAnatomyTimeouts) {
        anatomy = TNLRequestAnatomyDefault;
        TNLLogWarning(@"Invalid TNLRequestAnatomy provided!  Coersing to default.");
    }

    const TNLRequestAnatomyTimeouts timeouts = kAnatomyTimeouts[anatomy];
    return [[[self class] alloc] initWithIdleTimeout:timeouts.idleTimeout
                                      attemptTimeout:timeouts.attemptTimeout
                                    operationTimeout:timeouts.operationTimeout];
}

#pragma mark init

- (instancetype)initWithConfiguration:(nullable TNLRequestConfiguration *)config
{
    if (!config) {
        self = [self init];
    } else if ((self = [super init])) {
        _retryPolicyProvider = config->_retryPolicyProvider;
        _contentEncoder = config->_contentEncoder;
        _additionalContentDecoders = [config->_additionalContentDecoders copy];
        _URLCredentialStorage = config->_URLCredentialStorage;
        _URLCache = config->_URLCache;
        _cookieStorage = config->_cookieStorage;
        _sharedContainerIdentifier = [config->_sharedContainerIdentifier copy];

        memcpy(&_ivars, &(config->_ivars), sizeof(_ivars));
    }
    return self;
}

- (instancetype)init
{
    static NSURLSessionConfiguration *sTemplateConfig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTemplateConfig = [NSURLSessionConfiguration tnl_defaultSessionConfigurationWithNilPersistence];
    });
    TNLAssert(sTemplateConfig != nil);
    TNLAssert(!sTemplateConfig.URLCache);
    TNLAssert(!sTemplateConfig.URLCredentialStorage);
    TNLAssert(!sTemplateConfig.HTTPCookieStorage);
    return [self initWithSessionConfiguration:sTemplateConfig];
}

- (instancetype)initWithIdleTimeout:(NSTimeInterval)idleTimeout
                     attemptTimeout:(NSTimeInterval)attemptTimeout
                   operationTimeout:(NSTimeInterval)operationTimeout
{
    if (self = [self init]) {
        _ivars.idleTimeout = idleTimeout;
        _ivars.attemptTimeout = attemptTimeout;
        _ivars.operationTimeout = operationTimeout;
    }
    return self;
}

#pragma mark NSMutableCopying

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    TNLMutableRequestConfiguration *config = [[TNLMutableRequestConfiguration allocWithZone:zone] initWithConfiguration:self];
    return config;
}

#pragma mark Description

- (NSString *)description
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
#define D_SET(prop) \
    d[@"" #prop] = @(self.prop);

    D_SET(executionMode);
    D_SET(redirectPolicy);
    D_SET(responseDataConsumptionMode);
    D_SET(protocolOptions);
    D_SET(connectivityOptions);
    D_SET(contributeToExecutingNetworkConnectionsCount);
    D_SET(skipHostSanitization);
    D_SET(responseComputeHashAlgorithm);

    D_SET(attemptTimeout);
    D_SET(idleTimeout);
    D_SET(operationTimeout);
    D_SET(deferrableInterval);

    D_SET(cachePolicy);
    D_SET(networkServiceType);
    D_SET(cookieAcceptPolicy);
    D_SET(allowsCellularAccess);
    D_SET(isDiscretionary);
    D_SET(shouldLaunchAppForBackgroundEvents);
    D_SET(shouldSetCookies);
#if TARGET_OS_IOS
    if (tnl_available_ios_11) {
        D_SET(multipathServiceType);
    }
#endif

#undef D_SET
#define D_SET(prop) \
    if (self.prop) { \
        d[@"" #prop] = self.prop; \
    }

    D_SET(retryPolicyProvider);
    D_SET(contentEncoder);
    D_SET(additionalContentDecoders);

    D_SET(sharedContainerIdentifier);
    D_SET(URLCredentialStorage);
    D_SET(URLCache);
    D_SET(cookieStorage);

#undef D_SET

    return [NSString stringWithFormat:@"<%@ %p: %@>", NSStringFromClass([self class]), self, d];
}

#pragma mark Equivilence

- (NSUInteger)hash
{
    TNLMutableParameterCollection *params = TNLMutableParametersFromRequestConfiguration(self, nil, nil, nil);
    TNLMutableParametersStripURLCacheAndURLCredentialStorageAndCookieStorage(params);
    return params.hash +
           (NSUInteger)(self.responseComputeHashAlgorithm) +
           (NSUInteger)(self.contributeToExecutingNetworkConnectionsCount * 7) +
           (NSUInteger)(self.skipHostSanitization * 11) +
           (NSUInteger)(self.executionMode * 17);
}

- (BOOL)isEqual:(id)object
{
    if ([super isEqual:object]) {
        return YES;
    }

    if (![object isKindOfClass:[TNLRequestConfiguration class]]) {
        return NO;
    }

    TNLRequestConfiguration *other = object;

    if (0 != memcmp(&_ivars, &(other->_ivars), sizeof(_ivars))) {
        return NO;
    }

    if (self.retryPolicyProvider != other.retryPolicyProvider) {
        return NO;
    }

    if (self.sharedContainerIdentifier != other.sharedContainerIdentifier && ![self.sharedContainerIdentifier isEqualToString:other.sharedContainerIdentifier]) {
        return NO;
    }

    if (self.URLCredentialStorage != other.URLCredentialStorage) {
        return NO;
    }

    if (self.URLCache != other.URLCache) {
        return NO;
    }

    if (self.cookieStorage != other.cookieStorage) {
        return NO;
    }

    return YES;
}

@end

#pragma mark - TNLMutableRequestConfiguration

@implementation TNLMutableRequestConfiguration

@dynamic contributeToExecutingNetworkConnectionsCount;
@dynamic skipHostSanitization;
@dynamic responseComputeHashAlgorithm;

@dynamic executionMode;
@dynamic redirectPolicy;
@dynamic responseDataConsumptionMode;
@dynamic protocolOptions;
@dynamic connectivityOptions;

@dynamic retryPolicyProvider;
@dynamic contentEncoder;
@dynamic additionalContentDecoders;

@dynamic idleTimeout;
@dynamic attemptTimeout;
@dynamic operationTimeout;
@dynamic deferrableInterval;

@dynamic cachePolicy;
@dynamic networkServiceType;
@dynamic cookieAcceptPolicy;
@dynamic shouldSetCookies;
@dynamic allowsCellularAccess;
@dynamic discretionary;
@dynamic sharedContainerIdentifier;
@dynamic shouldLaunchAppForBackgroundEvents;
@dynamic URLCredentialStorage;
@dynamic URLCache;
@dynamic cookieStorage;
@dynamic multipathServiceType;

- (id)copyWithZone:(nullable NSZone *)zone
{
    TNLRequestConfiguration *config = [[TNLRequestConfiguration allocWithZone:zone] initWithConfiguration:self];
    return config;
}

- (void)setExecutionMode:(TNLRequestExecutionMode)executionMode
{
    _ivars.executionMode = executionMode;
}

- (void)setRedirectPolicy:(TNLRequestRedirectPolicy)redirectPolicy
{
    _ivars.redirectPolicy = redirectPolicy;
}

- (void)setResponseDataConsumptionMode:(TNLResponseDataConsumptionMode)responseDataConsumptionMode
{
    _ivars.responseDataConsumptionMode = responseDataConsumptionMode;
}

- (void)setProtocolOptions:(TNLRequestProtocolOptions)protocolOptions
{
    _ivars.protocolOptions = protocolOptions;
}

- (void)setConnectivityOptions:(TNLRequestConnectivityOptions)connectivityOptions
{
    _ivars.connectivityOptions = (connectivityOptions & 0xf);
}

- (void)setContributeToExecutingNetworkConnectionsCount:(BOOL)contributeToExecutingNetworkConnectionsCount
{
    _ivars.contributeToExecutingNetworkConnectionsCount = (contributeToExecutingNetworkConnectionsCount != NO);
}

- (void)setSkipHostSanitization:(BOOL)skipHostSanitization
{
    _ivars.skipHostSanitization = (skipHostSanitization != NO);
}

- (void)setResponseComputeHashAlgorithm:(TNLResponseHashComputeAlgorithm)responseComputeHashAlgorithm
{
    _ivars.responseComputeHashAlgorithm = responseComputeHashAlgorithm;
}

- (void)setRetryPolicyProvider:(nullable id<TNLRequestRetryPolicyProvider>)retryPolicyProvider
PROP_RETAIN_ASSIGN_IMP(retryPolicyProvider);

- (void)setContentEncoder:(nullable id<TNLContentEncoder>)contentEncoder
PROP_RETAIN_ASSIGN_IMP(contentEncoder);

- (void)setAdditionalContentDecoders:(nullable NSArray<id<TNLContentDecoder>> *)additionalContentDecoders
PROP_COPY_IMP(additionalContentDecoders);

- (void)setIdleTimeout:(NSTimeInterval)idleTimeout
{
    _ivars.idleTimeout = idleTimeout;
}

- (void)setAttemptTimeout:(NSTimeInterval)attemptTimeout
{
    _ivars.attemptTimeout = attemptTimeout;
}

- (void)setOperationTimeout:(NSTimeInterval)operationTimeout
{
    _ivars.operationTimeout = operationTimeout;
}

- (void)setDeferrableInterval:(NSTimeInterval)deferrableInterval
{
    _ivars.deferrableInterval = deferrableInterval;
}

- (void)setCachePolicy:(NSURLRequestCachePolicy)cachePolicy
{
    _ivars.cachePolicy = cachePolicy;
}

- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)networkServiceType
{
    _ivars.networkServiceType = networkServiceType;
}

- (void)setCookieAcceptPolicy:(NSHTTPCookieAcceptPolicy)cookieAcceptPolicy
{
    _ivars.cookieAcceptPolicy = cookieAcceptPolicy;
}

- (void)setShouldSetCookies:(BOOL)shouldSetCookies
{
    _ivars.shouldSetCookies = shouldSetCookies;
}

- (void)setAllowsCellularAccess:(BOOL)allowsCellularAccess
{
    _ivars.allowsCellularAccess = (allowsCellularAccess != NO);
}

- (void)setDiscretionary:(BOOL)discretionary
{
    _ivars.discretionary = (discretionary != NO);
}

- (void)setSharedContainerIdentifier:(nullable NSString *)sharedContainerIdentifier
{
    PROP_COPY_IMP(sharedContainerIdentifier);
}

- (void)setShouldLaunchAppForBackgroundEvents:(BOOL)shouldLaunchAppForBackgroundEvents
{
    _ivars.shouldLaunchAppForBackgroundEvents = (shouldLaunchAppForBackgroundEvents != NO);
}

- (void)setURLCredentialStorage:(nullable NSURLCredentialStorage *)URLCredentialStorage
PROP_RETAIN_ASSIGN_IMP(URLCredentialStorage);

- (void)setURLCache:(nullable NSURLCache *)URLCache
PROP_RETAIN_ASSIGN_IMP(URLCache);

- (void)setCookieStorage:(nullable NSHTTPCookieStorage *)cookieStorage
PROP_RETAIN_ASSIGN_IMP(cookieStorage);

- (void)setMultipathServiceType:(NSURLSessionMultipathServiceType)multipathServiceType
{
#if TARGET_OS_IOS
    if (tnl_available_ios_11) {
        _ivars.multipathServiceType = multipathServiceType;
    }
#endif
}

- (void)configureAsLowPriority
{
    self.discretionary = YES;
    self.deferrableInterval = TNLDeferrableIntervalForPriority(TNLPriorityLow);
    self.networkServiceType = NSURLNetworkServiceTypeBackground;
}

@end

#pragma mark TNLRequestConfiguration

@implementation TNLRequestConfiguration (Project)

+ (nullable instancetype)parseConfigurationFromIdentifier:(nullable NSString *)identifier
{
    if (!identifier) {
        return nil;
    }

    NSURL *url = [NSURL URLWithString:identifier];

    if (![url.scheme isEqualToString:TNLTwitterNetworkLayerURLScheme]) {
        return nil;
    }

    if (url.host.length == 0) {
        return nil;
    }

    NSArray *pathComponents = url.pathComponents;
    if (pathComponents.count != 3) {
        // 0 == '/' (root)
        // 1 == TNLRequestOperationQueue identifier
        // 2 == 'InApp' || 'Background'
        return nil;
    }

    NSString *version = [pathComponents[1] stringByReplacingOccurrencesOfString:@"_" withString:@"."];

    NSString *modeStr = pathComponents[2];
    TNLRequestExecutionMode mode = TNLRequestExecutionModeInApp;
    if ([modeStr isEqualToString:@"Background"]) {
        mode = TNLRequestExecutionModeBackground;
    }

    TNLParameterCollection *params = url.tnl_queryCollection;

    return [self configurationFromParameters:params
                               executionMode:mode
                                     version:version];
}

+ (instancetype)configurationFromParameters:(nullable TNLParameterCollection *)params
                              executionMode:(TNLRequestExecutionMode)mode
                                    version:(nullable NSString *)tnlVersion
{
    TNLMutableRequestConfiguration *mConfig = [TNLMutableRequestConfiguration defaultConfiguration];
    NSString *value;

#define PULL_VALUE(key, target, accessor, type) \
    do { \
        value = params[key]; \
        if (value) { \
            mConfig.target = ( type )[value accessor]; \
        } \
    } while (0)

    PULL_VALUE(TNLRequestConfigurationPropertyKeyRedirectPolicy, redirectPolicy, integerValue, TNLRequestRedirectPolicy);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyResponseDataConsumptionMode, responseDataConsumptionMode, integerValue, TNLResponseDataConsumptionMode);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyProtocolOptions, protocolOptions, integerValue, TNLRequestProtocolOptions);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyConnectivityOptions, connectivityOptions, integerValue, TNLRequestConnectivityOptions);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyIdleTimeout, idleTimeout, doubleValue, NSTimeInterval);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyAttemptTimeout, attemptTimeout, doubleValue, NSTimeInterval);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyOperationTimeout, operationTimeout, doubleValue, NSTimeInterval);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyDeferrableInterval, deferrableInterval, doubleValue, NSTimeInterval);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyCachePolicy, cachePolicy, integerValue, NSURLRequestCachePolicy);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyNetworkServiceType, networkServiceType, integerValue, NSURLRequestNetworkServiceType);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyCookieAcceptPolicy, cookieAcceptPolicy, integerValue, NSHTTPCookieAcceptPolicy);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyShouldSetCookies, shouldSetCookies, boolValue, BOOL);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyAllowsCellularAccess, allowsCellularAccess, boolValue, BOOL);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyDiscrectionary, discretionary, boolValue, BOOL);

    PULL_VALUE(TNLRequestConfigurationPropertyKeyShouldLaunchAppForBackgroundEvents, shouldLaunchAppForBackgroundEvents, boolValue, BOOL);

#if TARGET_OS_IOS
    if (tnl_available_ios_11) {
        PULL_VALUE(TNLRequestConfigurationPropertyKeyMultipathServiceType, multipathServiceType, integerValue, NSURLSessionMultipathServiceType);
    }
#endif

    mConfig.sharedContainerIdentifier = params[TNLRequestConfigurationPropertyKeySharedContainerIdentifier];

    // These cannot loaded from the params so it's best to have them be nil.
    // Having them be the default shared objects could hide that this constructor
    // doesn't actually load in these objects.
    mConfig.URLCredentialStorage = nil;
    mConfig.URLCache = nil;
    mConfig.cookieStorage = nil;

#undef PULL_VALUE

    mConfig.executionMode = mode;

    return mConfig;
}

- (void)applyDefaultTimeouts
{
    _ivars.idleTimeout = kConfigurationIdleTimeoutDefault;
    _ivars.attemptTimeout = kConfigurationAttemptTimeoutDefault;
    _ivars.operationTimeout = kConfigurationOperationTimeoutDefault;
    _ivars.deferrableInterval = kConfigurationDeferrableIntervalDefault;
}

@end

#pragma mark - Functions

NSURLCache * __nullable TNLUnwrappedURLCache(NSURLCache * __nullable cache)
{
    if (cache == [NSURLCache tnl_sharedURLCacheProxy]) {
        return [NSURLCache sharedURLCache];
    }
    return cache;
}

NSURLCredentialStorage * __nullable TNLUnwrappedURLCredentialStorage(NSURLCredentialStorage * __nullable storage)
{
    if (storage == [NSURLCredentialStorage tnl_sharedCredentialStorageProxy]) {
        return [NSURLCredentialStorage sharedCredentialStorage];
    }
    return storage;
}

NSHTTPCookieStorage * __nullable TNLUnwrappedCookieStorage(NSHTTPCookieStorage * __nullable storage)
{
    if (storage == [NSHTTPCookieStorage tnl_sharedHTTPCookieStorageProxy]) {
        return [NSHTTPCookieStorage sharedHTTPCookieStorage];
    }
    return storage;
}

void TNLMutableParametersStripURLCacheAndURLCredentialStorageAndCookieStorage(TNLMutableParameterCollection *params)
{
    params[TNLRequestConfigurationPropertyKeyURLCredentialStorage] = nil;
    params[TNLRequestConfigurationPropertyKeyURLCache] = nil;
    params[TNLRequestConfigurationPropertyKeyCookieStorage] = nil;
}

TNLMutableParameterCollection * __nullable TNLMutableParametersFromRequestConfiguration(TNLRequestConfiguration *config,
                                                                                        NSURLCache * __nullable canonicalCache,
                                                                                        NSURLCredentialStorage * __nullable canonicalCredentialStorage,
                                                                                        NSHTTPCookieStorage * __nullable canonicalCookieStorage)
{
    if (!config) {
        return nil;
    }

    if (!canonicalCache) {
        canonicalCache = TNLUnwrappedURLCache(config.URLCache);
    }
    if (!canonicalCredentialStorage) {
        canonicalCredentialStorage = TNLUnwrappedURLCredentialStorage(config.URLCredentialStorage);
    }
    if (!canonicalCookieStorage) {
        canonicalCookieStorage = TNLUnwrappedCookieStorage(config.cookieStorage);
    }

    TNLMutableParameterCollection *params = [[TNLMutableParameterCollection alloc] init];

    // Only for TNL layer (not NSURLSession)
    params[TNLRequestConfigurationPropertyKeyRedirectPolicy] = @(config.redirectPolicy);
    params[TNLRequestConfigurationPropertyKeyResponseDataConsumptionMode] = @(config.responseDataConsumptionMode);
    params[TNLRequestConfigurationPropertyKeyOperationTimeout] = @(config.operationTimeout);
    params[TNLRequestConfigurationPropertyKeyDeferrableInterval] = @(config.deferrableInterval);
    params[TNLRequestConfigurationPropertyKeyConnectivityOptions] = @(config.connectivityOptions);

    // For NSURLSession layer in the background
    params[TNLRequestConfigurationPropertyKeyIdleTimeout] = @(config.idleTimeout);
    params[TNLRequestConfigurationPropertyKeyAttemptTimeout] = @(config.attemptTimeout);
    params[TNLRequestConfigurationPropertyKeyShouldLaunchAppForBackgroundEvents] = @(config.shouldLaunchAppForBackgroundEvents);
#if TARGET_OS_IOS
    if (tnl_available_ios_11) {
        const NSURLSessionMultipathServiceType type = config.multipathServiceType;
        if (type != 0) {
            params[TNLRequestConfigurationPropertyKeyMultipathServiceType] = @(type);
        }
    }
#endif

    // Other properties

    params[TNLRequestConfigurationPropertyKeyProtocolOptions] = @(config.protocolOptions);
    params[TNLRequestConfigurationPropertyKeyConnectivityOptions] = @(config.connectivityOptions);
    params[TNLRequestConfigurationPropertyKeyCachePolicy] = @(config.cachePolicy);
    params[TNLRequestConfigurationPropertyKeyNetworkServiceType] = @(config.networkServiceType);
    params[TNLRequestConfigurationPropertyKeyAllowsCellularAccess] = @(config.allowsCellularAccess);
    params[TNLRequestConfigurationPropertyKeyDiscrectionary] = @(config.isDiscretionary);
    params[TNLRequestConfigurationPropertyKeyCookieAcceptPolicy] = @(config.cookieAcceptPolicy);
    params[TNLRequestConfigurationPropertyKeyShouldSetCookies] = @(config.shouldSetCookies);

    id value;

    value = config.sharedContainerIdentifier;
    if (value) {
        params[TNLRequestConfigurationPropertyKeySharedContainerIdentifier] = value;
    }

    value = canonicalCredentialStorage ?: config.URLCredentialStorage;
    if (value) {
        params[TNLRequestConfigurationPropertyKeyURLCredentialStorage] = [NSString stringWithFormat:@"%@_%p", NSStringFromClass([value class]), value];
    }

    value = canonicalCache ?: config.URLCache;
    if (value) {
        params[TNLRequestConfigurationPropertyKeyURLCache] = [NSString stringWithFormat:@"%@_%p", NSStringFromClass([value class]), value];
    }

    value = canonicalCookieStorage ?: config.cookieStorage;
    if (value) {
        params[TNLRequestConfigurationPropertyKeyCookieStorage] = [NSString stringWithFormat:@"%@_%p", NSStringFromClass([value class]), value];
    }

    /**
     Note:
     config.contributeToExecutingNetworkConnectionsCount,
     config.skipHostSanitization,
     config.responseComputeHashAlgorithm,
     config.contentEncoder,
     config.additionContentDecoders,
     config.retryPolicyProvider and
     config.executionMode
     are omitted on purpose.
     */

    return params;
}

NSArray *TNLProtocolClassesForProtocolOptions(TNLRequestProtocolOptions options)
{
    if (!options) {
        return nil;
    }

    NSMutableArray *protocols = [[NSMutableArray alloc] init];
    if (TNL_BITMASK_HAS_SUBSET_FLAGS(options, TNLRequestProtocolOptionPseudo)) {
        [protocols addObject:[TNLPseudoURLProtocol class]];
    }

    return protocols;
}

TNLRequestProtocolOptions TNLProtocolOptionsForProtocolClasses(NSArray * __nullable protocols)
{
    TNLRequestProtocolOptions options = 0;

    for (Class c in protocols) {
        if ([c isSubclassOfClass:[TNLPseudoURLProtocol class]]) {
            options |= TNLRequestProtocolOptionPseudo;
        }
    }

    return options;
}

void TNLRequestConfigurationAssociateWithRequest(TNLRequestConfiguration *config, NSURLRequest *request)
{
    TNLAssert(request);
    TNLAssert(config);
    if (request) {
        objc_setAssociatedObject(request, &kAssociatedConfigKey, config, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

TNLRequestConfiguration * __nullable TNLRequestConfigurationGetAssociatedWithRequest(NSURLRequest *request)
{
    TNLAssert(request);
    if (request) {
        return objc_getAssociatedObject(request, &kAssociatedConfigKey);
    }
    return nil;
}

NS_ASSUME_NONNULL_END

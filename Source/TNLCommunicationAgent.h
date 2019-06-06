//
//  TNLCommunicationAgent.h
//  TwitterNetworkLayer
//
//  Created on 5/2/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

#if !TARGET_OS_WATCH // no communication agent for watchOS

#import <SystemConfiguration/SystemConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TNLCarrierInfo;
@protocol TNLCommunicationAgentObserver;

/**
 Enum of reachability statuses from the `TNLCommunicationAgent`
 */
typedef NS_ENUM(NSInteger, TNLNetworkReachabilityStatus)
{
    /** Not yet determined reachability */
    TNLNetworkReachabilityUndetermined = -1,
    /** Unreachable */
    TNLNetworkReachabilityNotReachable = 0,
    /** reachable via 802.11 WiFi */
    TNLNetworkReachabilityReachableViaWiFi = 1,
    /** reachabile via WWAN (cellular) */
    TNLNetworkReachabilityReachableViaWWAN = 2,
};

//! Convert a `TNLNetworkReachabilityStatus` to an `NSString`
FOUNDATION_EXTERN NSString * __nonnull TNLNetworkReachabilityStatusToString(TNLNetworkReachabilityStatus status);

/**
 Enum of captive portal status from the `TNLCommunicationAgent`
 */
typedef NS_ENUM(NSInteger, TNLCaptivePortalStatus)
{
    /** not yet determined captive portal status */
    TNLCaptivePortalStatusUndetermined = -1,
    /** captive portal is not apparent */
    TNLCaptivePortalStatusNoCaptivePortal = 0,
    /** captive portal was detected */
    TNLCaptivePortalStatusCaptivePortalDetected = 1,
    /**
     captive portal cannot be detected due to ATS rules.
     In order to support captive portal detection, an ATS exception must be made for connectivitycheck.gstatic.com

       Update your `Info.plist` file to have an exception for connectivitycheck.gstatic.com like this:

         <key>NSAppTransportSecurity</key>
         <dict>
           <key>NSAllowsArbitraryLoads</key>
           <false/>
           <key>NSExceptionDomains</key>
           <dict>
             <key>connectivitycheck.gstatic.com</key>
             <dict>
               <key>NSExceptionAllowsInsecureHTTPLoads</key>
               <true/>
             </dict>
           </dict>
         </dict>

     */
    TNLCaptivePortalStatusDetectionBlockedByAppTransportSecurity = -100,
};

//! Convert a `TNLCaptivePortalStatus` to an `NSString`
FOUNDATION_EXTERN NSString * __nonnull TNLCaptivePortalStatusToString(TNLCaptivePortalStatus status);

/**
 An enum of known radio access technologies.
 See `CTRadioAccessTechnology` constants in `CTTelephonyNetworkInfo.h`
 */
typedef NS_ENUM(NSInteger, TNLWWANRadioAccessTechnologyValue) {
    /** Unknown radio access tech */
    TNLWWANRadioAccessTechnologyValueUnknown    = 0,

#if TARGET_OS_IOS && !TARGET_OS_UIKITFORMAC

    /** 2G, `CTRadioAccessTechnologyGPRS` */
    TNLWWANRadioAccessTechnologyValueGPRS       = 1,
    /** 2G, `CTRadioAccessTechnologyEdge` */
    TNLWWANRadioAccessTechnologyValueEDGE       = 2,
    /** 3G, `CTRadioAccessTechnologyWCDMA` */
    TNLWWANRadioAccessTechnologyValueUMTS       = 3,
    /** 3G, `CTRadioAccessTechnologyHSDPA` */
    TNLWWANRadioAccessTechnologyValueHSDPA      = 4,
    /** 3G, `CTRadioAccessTechnologyHSUPA` */
    TNLWWANRadioAccessTechnologyValueHSUPA      = 5,
    /** 3G, Not defined in `CTTelephonyNetworkInfo.h` */
    TNLWWANRadioAccessTechnologyValueHSPA       = 6,
    /** 2G, Not defined in `CTTelephonyNetworkInfo.h` */
    TNLWWANRadioAccessTechnologyValueCDMA       = 7,
    /** 1G, `CTRadioAccessTechnologyCDMAEVDORev0` */
    TNLWWANRadioAccessTechnologyValueEVDO_0     = 8,
    /** 3G, `CTRadioAccessTechnologyCDMAEVDORevA` */
    TNLWWANRadioAccessTechnologyValueEVDO_A     = 9,
    /** 3G, `CTRadioAccessTechnologyCDMAEVDORevB` */
    TNLWWANRadioAccessTechnologyValueEVDO_B     = 10,
    /** 1G, `CTRadioAccessTechnologyCDMA1x` */
    TNLWWANRadioAccessTechnologyValue1xRTT      = 11,
    /** 2G, Not defined in `CTTelephonyNetworkInfo.h` */
    TNLWWANRadioAccessTechnologyValueIDEN       = 12,
    /** 4G, `CTRadioAccessTechnologyLTE` */
    TNLWWANRadioAccessTechnologyValueLTE        = 13,
    /** 4G, `CTRadioAccessTechnologyeHRPD` */
    TNLWWANRadioAccessTechnologyValueEHRPD      = 14,
    /** 4G, Not defined in `CTTelephonyNetworkInfo.h` */
    TNLWWANRadioAccessTechnologyValueHSPAP      = 15

#endif // #if TARGET_OS_IOS && !TARGET_OS_UIKITFORMAC
};

//! Convert a WWAN radio access technololgy `NSString` into a `TNLWWANRadioAccessTechnologyValue`
FOUNDATION_EXTERN TNLWWANRadioAccessTechnologyValue TNLWWANRadioAccessTechnologyValueFromString(NSString * __nullable WWANTechString);
//! Convert a `TNLWWANRadioAccessTechnologyValue` into an `NSString`
FOUNDATION_EXTERN NSString * __nonnull TNLWWANRadioAccessTechnologyValueToString(TNLWWANRadioAccessTechnologyValue value);

/**
 Enum for the generation of a radio access technology
 */
typedef NS_ENUM(NSInteger, TNLWWANRadioAccessGeneration) {
    /** Unknown */
    TNLWWANRadioAccessGenerationUnknown = 0,
    /** 1G */
    TNLWWANRadioAccessGeneration1G = 1,
    /** 2G */
    TNLWWANRadioAccessGeneration2G = 2,
    /** 3G */
    TNLWWANRadioAccessGeneration3G = 3,
    /** 4G */
    TNLWWANRadioAccessGeneration4G = 4
};

//! Determine the `TNLWWANRadioAccessGeneration` from a `TNLWWANRadioAccessTechnologyValue`
FOUNDATION_EXTERN TNLWWANRadioAccessGeneration TNLWWANRadioAccessGenerationForTechnologyValue(TNLWWANRadioAccessTechnologyValue value) __attribute__((const));

//! String to break SCNetworkReachabilityFlags into a string of flags - for debug purposes only
FOUNDATION_EXTERN NSString *TNLDebugStringFromNetworkReachabilityFlags(SCNetworkReachabilityFlags flags);


typedef void(^TNLCommunicationAgentIdentifyReachabilityCallback)(SCNetworkReachabilityFlags flags, TNLNetworkReachabilityStatus status);
typedef void(^TNLCommunicationAgentIdentifyCarrierInfoCallback)(id<TNLCarrierInfo> __nullable info);
typedef void(^TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback)(NSString * __nullable info);
typedef void(^TNLCommunicationAgentIdentifyCaptivePortalStatusCallback)(TNLCaptivePortalStatus status);

/**
 An agent for observing and determing traits regarding communication, including:
   - network reachability
   - carrier info
   - radio info
   - captive portal status
 @warning There are known regressions since iOS 10 in SystemConfiguration for observing
 reachability.  These issues range from reachability events not working at all on simulator to
 getting into a state where reachability returning does not trigger events.
 @warning As always with reachability APIs, do _NOT_ rely on the reachability state as a gate prevent
 triggering a network request.  Always fire the networking request and use reachability as a helper
 signal, not a canonical source of truth.  Seriously... don't block your app on reachability, that
 leads to nothing but pain.
 @note In order for captive portal status detection to work, an ATS exception must be made for
 connectivitycheck.gstatic.com to permit insecure HTTP requests.
 See `TNLCaptivePortalStatusDetectionBlockedByAppTransportSecurity` for more.
 */
@interface TNLCommunicationAgent : NSObject

/** the network host for the agent */
@property (nonatomic, copy, readonly) NSString *host;

/** designated initializer */
- (instancetype)initWithInternetReachabilityHost:(NSString *)host NS_DESIGNATED_INITIALIZER;

/** unavailable */
- (instancetype)init NS_UNAVAILABLE;
/** unavailable */
+ (instancetype)new NS_UNAVAILABLE;

/** identify the reachability asynchronously (callback on main thread) */
- (void)identifyReachability:(TNLCommunicationAgentIdentifyReachabilityCallback)callback;
/** identify the carrier info asynchronously (callback on main thread) */
- (void)identifyCarrierInfo:(TNLCommunicationAgentIdentifyCarrierInfoCallback)callback;
/** identify the WWAN radio access technology asynchronously (callback on main thread) */
- (void)identifyWWANRadioAccessTechnology:(TNLCommunicationAgentIdentifyWWANRadioAccessTechnologyCallback)callback;
/** identify the captive portal status (callback on main thread) */
- (void)identifyCaptivePortalStatus:(TNLCommunicationAgentIdentifyCaptivePortalStatusCallback)callback;

/**
 add an observer for when communication traits update.
 _observer_ is held weakly.
 Callbacks will be made on the main thread.
 */
- (void)addObserver:(id<TNLCommunicationAgentObserver>)observer;
/**
 explicitely remove an observer.
 */
- (void)removeObserver:(id<TNLCommunicationAgentObserver>)observer;

@end

/** _No LAN_ reachability ;P */
@interface TNLCommunicationAgent (LANReachability)

/** unavailable */
@property (nonatomic, readonly) TNLNetworkReachabilityStatus cachedLANReachabilityStatus __attribute__((unavailable("LAN reachability is unavailable")));
/** unavailable */
- (void)identifyLANReachability:(TNLCommunicationAgentIdentifyReachabilityCallback)callback __attribute__((unavailable("LAN reachability is unavailable")));

@end

/**
 Category for accessing cached properties.
 It is recommended to use either a `TNLCommunicationAgentObserver` or one of the `identify` methods
 instead, though.
 */
@interface TNLCommunicationAgent (CachedProperties)

/** cached reachability status */
@property (atomic, readonly) TNLNetworkReachabilityStatus currentReachabilityStatus;
/** cached reachability flags */
@property (atomic, readonly) SCNetworkReachabilityFlags currentReachabilityFlags;
/** cached radio access technology. Note: `nil` for macOS and UIKit for Mac */
@property (atomic, copy, readonly, nullable) NSString *currentWWANRadioAccessTechnology;
/** cached captive portal status */
@property (atomic, readonly) TNLCaptivePortalStatus currentCaptivePortalStatus;

/** cached carrier info. Note: `nil` for macOS and UIKit for Mac as there is no cellular carrier information */
@property (atomic, readonly, nullable) id<TNLCarrierInfo> currentCarrierInfo; // or use `synchronousCarrierInfo`, which is more robust but can be slower

@end

/** Unsafe category */
@interface TNLCommunicationAgent (UnsafeSynchronousAccess)
/** access the carrier info synchronously */
- (nullable id<TNLCarrierInfo>)synchronousCarrierInfo __attribute__((deprecated("should not access carrier info synchronously!  Use identifyCarrierInfo: instead")));
@end

/** protocol for observer of communication traits via `TNLCommunicationAgent` */
@protocol TNLCommunicationAgentObserver <NSObject>

@optional

/**
 called when the oberver is registered with the initial trait values at the time of registration

 @parameter communicationAgent related comminication agent for registration
 @parameter didRegisterObserverWithInitialReachabilityFlags Reachability configuration flags that were registered
 @parameter status current network reachability status
 @parameter carrierInfo Any available carrier information.  Note: This is `nil` in macOS as there is no cellular carrier involved.
 @parameter WWANRadioAccessTechnology GPRS, EDGE, LTE, etc. Note: This is `nil` in macOS as there is no cellular carrier involved.
 @parameter captivePortalStatus the `TNLCaptivePortalStatus` upon registration of an observer
 */
- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didRegisterObserverWithInitialReachabilityFlags:(SCNetworkReachabilityFlags)flags
        status:(TNLNetworkReachabilityStatus)status
        carrierInfo:(nullable id<TNLCarrierInfo>)info
        WWANRadioAccessTechnology:(nullable NSString *)radioTech
        captivePortalStatus:(TNLCaptivePortalStatus)captivePortalStatus;

/** called when reachability changes */
- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didUpdateReachabilityFromPreviousFlags:(SCNetworkReachabilityFlags)oldFlags
        previousStatus:(TNLNetworkReachabilityStatus)oldStatus
        toCurrentFlags:(SCNetworkReachabilityFlags)newFlags
        currentStatus:(TNLNetworkReachabilityStatus)newStatus;

/** called when carrier info changes

 @parameter communicationAgent related comminication agent for registration
 @parameter didUpdateCarrierFromPreviousInfo Existing carrier information if available.  Note: This is `nil` in macOS as there is no cellular carrier involved.
 @parameter toCurrentInfo New carrier information if available.  Note: This is `nil` in macOS as there is no cellular carrier involved.
 */
- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didUpdateCarrierFromPreviousInfo:(nullable id<TNLCarrierInfo>)oldInfo
        toCurrentInfo:(nullable id<TNLCarrierInfo>)newInfo;

/** called when WWAN radio access technology changes */
- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didUpdateWWANRadioAccessTechnologyFromPreviousTech:(nullable NSString *)oldTech
        toCurrentTech:(nullable NSString *)newTech;

/** called when captive portal status changes */
- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didUpdateCaptivePortalStatusFromPreviousStatus:(TNLCaptivePortalStatus)oldStatus
        toCurrentStatus:(TNLCaptivePortalStatus)newStatus;

@end

/** Carrier info, matching `CTCarrier` */
@protocol TNLCarrierInfo <NSObject>

/**
 An `NSString` containing the name of the subscriber's cellular service provider.
 */
@property (nonatomic, readonly, copy, nullable) NSString *carrierName;

/**
 An `NSString` containing the mobile country code for the subscriber's cellular service provider,
 in its numeric representation
 */
@property (nonatomic, readonly, copy, nullable) NSString *mobileCountryCode;

/**
 An `NSString` containing the  mobile network code for the subscriber's cellular service provider,
 in its numeric representation
 */
@property (nonatomic, readonly, copy, nullable) NSString *mobileNetworkCode;

/**
 Returns an `NSString` object that contains country code for the subscriber's cellular service
 provider, represented as an ISO 3166-1 country code string
 */
@property (nonatomic, readonly, copy, nullable) NSString* isoCountryCode;

/**
 A `BOOL` value that is `YES` if this carrier allows VOIP calls to be made on its network,
 `NO` otherwise.
 */
@property (nonatomic, readonly) BOOL allowsVOIP;

@end

NS_ASSUME_NONNULL_END

#endif // !TARGET_OS_WATCH

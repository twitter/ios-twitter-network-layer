//
//  TNLInternalKeys.h
//  TwitterNetworkLayer
//
//  Created by Nolan O'Brien on 6/15/18.
//  Copyright © 2018 Twitter. All rights reserved.
//

#pragma mark Global Keys

#define TNLTwitterNetworkLayerURLScheme @"tnl"

#pragma mark Shared Keys between URL Sessions and TNL Request Configs

#define kSharedKeyRequestCachePolicy        @"rcp"
#define kSharedKeyNetworkServiceType        @"nst"
#define kSharedKeyAllowsCellularAccess      @"aca"
#define kSharedKeyDiscretionary             @"dis"
#define kSharedKeyURLCredentialStorage      @"crdsto"
#define kSharedKeyURLCache                  @"urlcch"
#define kSharedKeyHTTPCookieStorage         @"ckisto"
#define kSharedKeyHTTPCookieAcceptPolicy    @"ckiplcy"
#define kSharedKeyHTTPShouldSetCookies      @"setcki"
#define kSharedKeySharedContainerIdentifier @"scid"
#define kSharedKeySessionSendsLaunchEvents  @"ssle"
#define kSharedKeyMultiPathServiceType      @"mptcp" // Multipath TCP (MPTCP)

#pragma mark Keys for URL Sessions Configs

#define TNLSessionConfigurationPropertyKeyRequestCachePolicy            kSharedKeyRequestCachePolicy
#define TNLSessionConfigurationPropertyKeyTimeoutIntervalForRequest     @"toi4req"
#define TNLSessionConfigurationPropertyKeyTimeoutIntervalForResource    @"toi4rsc"
#define TNLSessionConfigurationPropertyKeyNetworkServiceType            kSharedKeyNetworkServiceType
#define TNLSessionConfigurationPropertyKeyAllowsCellularAccess          kSharedKeyAllowsCellularAccess
#define TNLSessionConfigurationPropertyKeyWaitsForConnectivity          @"w4c"
#define TNLSessionConfigurationPropertyKeyDiscretionary                 kSharedKeyDiscretionary
#define TNLSessionConfigurationPropertyKeySessionSendsLaunchEvents      kSharedKeySessionSendsLaunchEvents
#define TNLSessionConfigurationPropertyKeyConnectionProxyDictionary     @"cpd"
#define TNLSessionConfigurationPropertyKeyTLSMinimumSupportedProtocol   @"tlsmin"
#define TNLSessionConfigurationPropertyKeyTLSMaximumSupportedProtocol   @"tlsmax"
#define TNLSessionConfigurationPropertyKeyHTTPShouldUsePipelining       @"ppln"
#define TNLSessionConfigurationPropertyKeyHTTPShouldSetCookies          kSharedKeyHTTPShouldSetCookies
#define TNLSessionConfigurationPropertyKeyHTTPCookieAcceptPolicy        kSharedKeyHTTPCookieAcceptPolicy
#define TNLSessionConfigurationPropertyKeyHTTPAdditionalHeaders         @"hdrs"
#define TNLSessionConfigurationPropertyKeyHTTPMaximumConnectionsPerHost @"maxcon"
#define TNLSessionConfigurationPropertyKeyHTTPCookieStorage             kSharedKeyHTTPCookieStorage
#define TNLSessionConfigurationPropertyKeyURLCredentialStorage          kSharedKeyURLCredentialStorage
#define TNLSessionConfigurationPropertyKeyURLCache                      kSharedKeyURLCache
#define TNLSessionConfigurationPropertyKeySharedContainerIdentifier     kSharedKeySharedContainerIdentifier
#define TNLSessionConfigurationPropertyKeyProtocolClassPrefix           @"pc" // key will be this prefix concatenated with an index
#define TNLSessionConfigurationPropertyKeyMultipathServiceType          kSharedKeyMultiPathServiceType

#pragma mark Keys for TNL Request Configs

#define TNLRequestConfigurationPropertyKeyRedirectPolicy                        @"rdp"
#define TNLRequestConfigurationPropertyKeyResponseDataConsumptionMode           @"rdcm"
#define TNLRequestConfigurationPropertyKeyProtocolOptions                       @"ptcls"
#define TNLRequestConfigurationPropertyKeyConnectivityOptions                   @"cnvty"
#define TNLRequestConfigurationPropertyKeyIdleTimeout                           @"idlTO"
#define TNLRequestConfigurationPropertyKeyAttemptTimeout                        @"atmpTO"
#define TNLRequestConfigurationPropertyKeyOperationTimeout                      @"opTO"
#define TNLRequestConfigurationPropertyKeyDeferrableInterval                    @"dfrI"
#define TNLRequestConfigurationPropertyKeyCookieAcceptPolicy                    kSharedKeyHTTPCookieAcceptPolicy
#define TNLRequestConfigurationPropertyKeyCachePolicy                           kSharedKeyRequestCachePolicy
#define TNLRequestConfigurationPropertyKeyNetworkServiceType                    kSharedKeyNetworkServiceType
#define TNLRequestConfigurationPropertyKeyAllowsCellularAccess                  kSharedKeyAllowsCellularAccess
#define TNLRequestConfigurationPropertyKeyDiscrectionary                        kSharedKeyDiscretionary
#define TNLRequestConfigurationPropertyKeyShouldLaunchAppForBackgroundEvents    kSharedKeySessionSendsLaunchEvents
#define TNLRequestConfigurationPropertyKeyShouldSetCookies                      kSharedKeyHTTPShouldSetCookies
#define TNLRequestConfigurationPropertyKeyURLCredentialStorage                  kSharedKeyURLCredentialStorage
#define TNLRequestConfigurationPropertyKeyURLCache                              kSharedKeyURLCache
#define TNLRequestConfigurationPropertyKeyCookieStorage                         kSharedKeyHTTPCookieStorage
#define TNLRequestConfigurationPropertyKeySharedContainerIdentifier             kSharedKeySharedContainerIdentifier
#define TNLRequestConfigurationPropertyKeyMultipathServiceType                  kSharedKeyMultiPathServiceType


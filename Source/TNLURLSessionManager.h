//
//  TNLURLSessionManager.h
//  TwitterNetworkLayer
//
//  Created on 10/23/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLGlobalConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

@class TNLRequestOperationQueue;
@class TNLURLSessionTaskOperation;
@protocol TNLRequestOperationCancelSource;

#pragma mark Functions

FOUNDATION_EXTERN TNLMutableParameterCollection * __nullable
TNLMutableParametersFromURLSessionConfiguration(NSURLSessionConfiguration * __nullable config);

FOUNDATION_EXTERN void
TNLMutableParametersStripNonURLSessionProperties(TNLMutableParameterCollection *params,
                                                 TNLRequestExecutionMode mode);

FOUNDATION_EXTERN BOOL
TNLURLSessionIdentifierIsTaggedForTNL(NSString *identifier);

#pragma mark Constants

FOUNDATION_EXTERN NSTimeInterval TNLGlobalServiceUnavailableRetryAfterBackoffValueDefault;
FOUNDATION_EXTERN NSTimeInterval TNLGlobalServiceUnavailableRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway;

#pragma mark Declarations

typedef void(^TNLRequestOperationQueueFindTaskOperationCompleteBlock)(TNLURLSessionTaskOperation * taskOp);

#pragma mark TNLURLSessionManager

@protocol TNLURLSessionManager <NSObject>

- (void)cancelAllWithSource:(id<TNLRequestOperationCancelSource>)source
            underlyingError:(nullable NSError *)optionalUnderlyingError;

- (void)findURLSessionTaskOperationForRequestOperationQueue:(TNLRequestOperationQueue *)queue
                                           requestOperation:(TNLRequestOperation *)op
                                                   complete:(TNLRequestOperationQueueFindTaskOperationCompleteBlock)complete;
- (BOOL)handleBackgroundURLSessionEvents:(NSString *)identifier
                       completionHandler:(dispatch_block_t)completionHandler;
- (void)URLSessionDidCompleteBackgroundEvents:(NSURLSession *)session;
- (void)URLSessionDidCompleteBackgroundTask:(NSUInteger)taskIdentifier
                    sessionConfigIdentifier:(NSString *)sessionConfigIdentifier
                  sharedContainerIdentifier:(nullable NSString *)sharedContainerIdentifier
                                    request:(NSURLRequest *)request
                                   response:(TNLResponse *)response;

- (void)syncAddURLSessionTaskOperation:(TNLURLSessionTaskOperation *)op;
- (void)applyServiceUnavailableBackoffDependenciesToOperation:(NSOperation *)op
                                                      withURL:(NSURL *)URL
                                            isLongPollRequest:(BOOL)isLongPoll;
- (void)serviceUnavailableEncounteredForURL:(NSURL *)URL
                            retryAfterDelay:(NSTimeInterval)delay;
@property (atomic) TNLGlobalConfigurationServiceUnavailableBackoffMode serviceUnavailableBackoffMode;

@end

NS_ROOT_CLASS
@interface TNLURLSessionManager
+ (id<TNLURLSessionManager>)sharedInstance;
@end

#pragma mark URL Session with TNLRequestConfiguration

@interface TNLRequestConfiguration (URLSession)

+ (instancetype)configurationWithSessionConfiguration:(nullable NSURLSessionConfiguration *)sessionConfiguration;
- (instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)config;

- (NSURLSessionConfiguration *)generateCanonicalSessionConfiguration;
- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode;
- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationForBackgroundModeWithIdentifier:(nullable NSString *)identifier;
- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode identifier:(nullable NSString *)identifier;
- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode identifier:(nullable NSString *)identifier canonicalURLCache:(nullable NSURLCache *)canonicalCache canonicalURLCredentialStorage:(nullable NSURLCredentialStorage *)canonicalCredentialStorage canonicalCookieStorage:(nullable NSHTTPCookieStorage *)canonicalCookieStorage;

- (void)applySettingsToSessionConfiguration:(nullable NSURLSessionConfiguration *)config;

@end

@interface NSURLSessionConfiguration (TNLRequestConfiguration)

+ (NSURLSessionConfiguration *)sessionConfigurationWithConfiguration:(TNLRequestConfiguration *)configuration;
+ (NSURLSessionConfiguration *)tnl_defaultSessionConfigurationWithNilPersistence;

@end

#pragma mark Background Session with Tagged Identifier

@interface NSURLSessionConfiguration (TaggedIdentifier)

+ (instancetype)tnl_backgroundSessionConfigurationWithTaggedIdentifier:(NSString *)identifier;

@end

#pragma mark Keys for URL Sessions Configs

FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyRequestCachePolicy;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyTimeoutIntervalForRequest;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyTimeoutIntervalForResource;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyNetworkServiceType;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyAllowsCellularAccess;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyDiscretionary;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeySessionSendsLaunchEvents;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyConnectionProxyDictionary;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyTLSMinimumSupportedProtocol;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyTLSMaximumSupportedProtocol;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyHTTPShouldUsePipelining;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyHTTPShouldSetCookies;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyHTTPCookieAcceptPolicy;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyHTTPAdditionalHeaders;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyHTTPMaximumConnectionsPerHost;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyHTTPCookieStorage;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyURLCredentialStorage;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyURLCache;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeySharedContainerIdentifier;
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyProtocolClassPrefix; // key will be this prefix concatenated with an index
FOUNDATION_EXTERN NSString * const TNLSessionConfigurationPropertyKeyMultipathServiceType;

NS_ASSUME_NONNULL_END

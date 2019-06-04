//
//  TNLURLSessionManager.h
//  TwitterNetworkLayer
//
//  Created on 10/23/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLGlobalConfiguration.h>
#import <TwitterNetworkLayer/TNLRequestConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

@class TNLMutableParameterCollection;
@class TNLRequestOperationQueue;
@class TNLResponse;
@class TNLURLSessionTaskOperation;
@protocol TNLRequestOperationCancelSource;

#pragma mark Functions

FOUNDATION_EXTERN TNLMutableParameterCollection * __nullable
TNLMutableParametersFromURLSessionConfiguration(NSURLSessionConfiguration * __nullable config);

FOUNDATION_EXTERN BOOL
TNLURLSessionIdentifierIsTaggedForTNL(NSString *identifier);

#pragma mark Constants

FOUNDATION_EXTERN NSTimeInterval TNLGlobalServiceUnavailableRetryAfterBackoffValueDefault;
FOUNDATION_EXTERN NSTimeInterval TNLGlobalServiceUnavailableRetryAfterMaximumBackoffValueBeforeTreatedAsGoAway;

#pragma mark Declarations

typedef void(^TNLRequestOperationQueueFindTaskOperationCompleteBlock)(TNLURLSessionTaskOperation * taskOp);
typedef void(^TNLURLSessionManagerGetAllSessionsCallback)(NSArray<NSURLSession *> *foregroundSessions, NSArray<NSURLSession *> *backgroundSessions);

#pragma mark TNLURLSessionManager

@protocol TNLURLSessionManager <NSObject>

- (void)cancelAllForQueue:(TNLRequestOperationQueue *)queue
                   source:(id<TNLRequestOperationCancelSource>)source
          underlyingError:(nullable NSError *)optionalUnderlyingError;

- (void)findURLSessionTaskOperationForRequestOperationQueue:(TNLRequestOperationQueue *)queue
                                           requestOperation:(TNLRequestOperation *)op
                                                   complete:(TNLRequestOperationQueueFindTaskOperationCompleteBlock)complete;
- (void)getAllURLSessions:(TNLURLSessionManagerGetAllSessionsCallback)callback;
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

- (void)pruneUnusedURLSessions;
- (void)pruneURLSessionMatchingRequestConfiguration:(TNLRequestConfiguration *)config
                                   operationQueueId:(nullable NSString *)operationQueueId;

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
- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode
                                                                           identifier:(nullable NSString *)identifier;
- (NSURLSessionConfiguration *)generateCanonicalSessionConfigurationWithExecutionMode:(TNLRequestExecutionMode)mode
                                                                           identifier:(nullable NSString *)identifier
                                                                    canonicalURLCache:(nullable NSURLCache *)canonicalCache
                                                        canonicalURLCredentialStorage:(nullable NSURLCredentialStorage *)canonicalCredentialStorage
                                                               canonicalCookieStorage:(nullable NSHTTPCookieStorage *)canonicalCookieStorage;

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

NS_ASSUME_NONNULL_END

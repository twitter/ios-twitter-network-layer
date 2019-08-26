//
//  TNLXAppDelegate.m
//  TNLExample
//
//  Created on 7/24/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import "TAPI.h"
#import "TNLXAppDelegate.h"
#import "TNLXImageSupport.h"
#import "TNLXNetworkHeuristicObserver.h"

NSString *TNLXCommunicationStatusUpdatedNotification = @"TNLXCommunicationStatusUpdatedNotification";

@interface TNLXAppDelegate () <TNLNetworkObserver, TNLLogger, TNLCommunicationAgentObserver>
@end

@implementation TNLXAppDelegate
{
    IBOutlet UITabBarController *_tabBarController;

    TNLCommunicationAgent *_commAgent;
    NSString *_communicationStatusDescription;
    NSString *_SCFlagsString;
    NSString *_statusString;
    NSString *_carrierName;
    NSString *_radioTech;
}

- (BOOL)tnl_canLogWithLevel:(TNLLogLevel)level context:(id)context
{
    return level <= TNLLogLevelDebug;
}

- (void)tnl_logWithLevel:(TNLLogLevel)level context:(id)context file:(NSString *)file function:(NSString *)function line:(int)line message:(NSString *)message
{
    NSString *levelString = nil;
    switch (level) {
        case TNLLogLevelEmergency:
        case TNLLogLevelAlert:
        case TNLLogLevelCritical:
        case TNLLogLevelError:
            levelString = @"ERR";
            break;
        case TNLLogLevelWarning:
            levelString = @"WRN";
            break;
        case TNLLogLevelNotice:
        case TNLLogLevelInformation:
            levelString = @"INF";
            break;
        case TNLLogLevelDebug:
            levelString = @"DBG";
            break;
    }

    NSLog(@"[%@]: %@", levelString, message);
}

- (BOOL)tnl_shouldRedactHTTPHeaderField:(nonnull NSString *)headerField
{
    if ([headerField isEqualToString:@"Authorization"]) {
        return YES;
    }
    return NO;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    // Set up logging
    [TNLGlobalConfiguration sharedInstance].logger = self;

    // Prepare network "business" observer
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(networkingDidChange:)
                                                 name:TNLNetworkExecutingNetworkConnectionsDidUpdateNotification
                                               object:nil];

    // Prepare global settings
    _commAgent = [[TNLCommunicationAgent alloc] initWithInternetReachabilityHost:@"api.twitter.com"];
    (void)[TNLXNetworkHeuristicObserver sharedInstance];
    [[TNLGlobalConfiguration sharedInstance] addNetworkObserver:self];
    [[TNLGlobalConfiguration sharedInstance] setAssertsEnabled:YES];
    [[TNLGlobalConfiguration sharedInstance] setMetricProvidingCommunicationAgent:_commAgent];
    [_commAgent addObserver:self];

    // Prepare Twitter API
    TAPIClient *client = [TAPIClient sharedInstance];
    NSString *consumerKey = [[NSBundle mainBundle] infoDictionary][@"tnlx_oauth_consumer_key"];
    NSString *consumerSecret = [[NSBundle mainBundle] infoDictionary][@"tnlx_oauth_consumer_secret"];
    if (consumerKey.length > 0 && consumerSecret.length > 0) {
        client.oauthConsumerKey = consumerKey;
        client.oauthConsumerSecret = consumerSecret;
    }
    __weak typeof(self) weakSelf = self;
    client.loginAccessBlock = ^(TAPILoginAccessCompletionBlock completion) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, nil);
        } else {
            [strongSelf promptForTwitterAPIAccess:completion];
        }
    };

    [self.window makeKeyAndVisible];

    return YES;
}

- (void)application:(nonnull UIApplication *)application handleEventsForBackgroundURLSession:(nonnull NSString *)identifier completionHandler:(nonnull void (^)(void))completionHandler
{
    NSLog(@"%@ %@", NSStringFromSelector(_cmd), identifier);
    if (![TNLRequestOperationQueue handleBackgroundURLSessionEvents:identifier completionHandler:completionHandler]) {
        completionHandler();
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 13, *)) {

    } else {
        application.networkActivityIndicatorVisible = [TNLNetwork hasExecutingNetworkConnections];
    }
#endif
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TNLResponse *)response
{
    TNLAttemptMetrics *lastAttemptMetrics = response.metrics.attemptMetrics.lastObject;
    TNLAttemptMetaData *metaData = lastAttemptMetrics.metaData;

    int64_t downloadByteCount = metaData.layer8BodyBytesReceived;
    NSTimeInterval duration = response.metrics.totalDuration;
    BOOL isCached = response.info.source == TNLResponseSourceLocalCache;
    BOOL errorWasEncountered = response.operationError != nil;
    if (downloadByteCount < 0 || duration <= 0 || isCached) {
        return;
    }

    double bytes = downloadByteCount;
    double bps = bytes/duration;

    static NSByteCountFormatter *bpsFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bpsFormatter = [[NSByteCountFormatter alloc] init];
        bpsFormatter.countStyle = NSByteCountFormatterCountStyleBinary;
        bpsFormatter.allowedUnits = NSByteCountFormatterUseKB;
        bpsFormatter.zeroPadsFractionDigits = YES;
        bpsFormatter.adaptive = YES;
    });
    NSLog(@"Bandwidth - %@ / %.2fs = %@ps%@", [bpsFormatter stringFromByteCount:downloadByteCount], duration, isnan(bps) ?@"NaN B" : [bpsFormatter stringFromByteCount:(long long)bps], errorWasEncountered ? @" DNF!" : @"");

    if ([response isKindOfClass:[TAPIResponse class]]) {
        NSError *error = [(TAPIResponse *)response anyError];
        if ([error.domain isEqualToString:TNLErrorDomain]) {
            if (error.code == TNLErrorCodeRequestOperationFailedToAuthorizeRequest) {
                error = error.userInfo[NSUnderlyingErrorKey];
            }
        }

        if ([error.domain isEqualToString:TAPIOperationErrorDomain]) {
            if (error.code == TAPIOperationErrorCodeMissingAccessCredentials) {
                [self warnThatAccessCredentialsAreMissing];
            } else if (error.code == TAPIOperationErrorCodeMissingConsumerCredentials) {
                [self warnThatConsumerCredentialsAreMissing];
            }
        }
    }
}

- (void)networkingDidChange:(NSNotification *)note
{
    assert([NSThread isMainThread]);
#if !TARGET_OS_MACCATALYST
    BOOL on = [note.userInfo[TNLNetworkExecutingNetworkConnectionsExecutingKey] boolValue];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = on;
#endif
}

- (void)promptForTwitterAPIAccess:(TAPILoginAccessCompletionBlock)completion
{
    // Just load from bundle - a proper app would have a way for users to log in
    NSString *token = [[NSBundle mainBundle] infoDictionary][@"tnlx_oauth_access_token"];
    NSString *secret = [[NSBundle mainBundle] infoDictionary][@"tnlx_oauth_access_secret"];
    if (token && secret) {
        completion(token, secret);
        return;
    }
    completion(nil, nil);
}

- (void)warnThatConsumerCredentialsAreMissing
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Missing Consumer Key & Secret"
                                                                   message:@"Twitter API credentials can be obtained by going to apps.twitter.com.\nPut them in TNLExample-Info.plist under `tnlx_oauth_consumer_key` and `tnlx_oauth_consumer_secret`."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:NULL]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:NULL];
}

- (void)warnThatAccessCredentialsAreMissing
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enter Access Token & Secret"
                                                                   message:@"Twitter API credentials can be obtained by going to apps.twitter.com.\nPut them in TNLExample-Info.plist under `tnlx_oauth_access_token` and `tnlx_oauth_access_secret`."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:NULL]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:NULL];
}

#pragma mark TNLCommunicationAgentObserver

- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didRegisterObserverWithInitialReachabilityFlags:(TNLNetworkReachabilityFlags)flags
        status:(TNLNetworkReachabilityStatus)status
        carrierInfo:(nullable id<TNLCarrierInfo>)info
        WWANRadioAccessTechnology:(nullable NSString *)radioTech
        captivePortalStatus:(TNLCaptivePortalStatus)captivePortalStatus
{
    _SCFlagsString = TNLDebugStringFromNetworkReachabilityFlags(flags);
    _statusString = TNLNetworkReachabilityStatusToString(status) ?: @"<null>";
    _carrierName = info.carrierName ?: @"<null>";
    _radioTech = [radioTech stringByReplacingOccurrencesOfString:@"CTRadioAccessTechnology" withString:@""] ?: @"<null>";

    NSDictionary *logInfo = @{
                              @"SC_flags" : _SCFlagsString,
                              @"status" : _statusString,
                              @"carrier" : info ?: (id)@"<null>",
                              @"radioTech" : _radioTech,
                              };
    NSLog(@"did register: %@", logInfo);
    [self _updateCommunicationStatusDescription];
}

- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didUpdateReachabilityFromPreviousFlags:(TNLNetworkReachabilityFlags)oldFlags
        previousStatus:(TNLNetworkReachabilityStatus)oldStatus
        toCurrentFlags:(TNLNetworkReachabilityFlags)newFlags
        currentStatus:(TNLNetworkReachabilityStatus)newStatus
{
    _SCFlagsString = TNLDebugStringFromNetworkReachabilityFlags(newFlags);
    _statusString = TNLNetworkReachabilityStatusToString(newStatus) ?: @"<null>";

    NSDictionary *logInfo = @{
                              @"SC_flags_old" : TNLDebugStringFromNetworkReachabilityFlags(oldFlags),
                              @"SC_flags_new" : _SCFlagsString,
                              @"status_old" : TNLNetworkReachabilityStatusToString(oldStatus) ?: @"<null>",
                              @"status_new" : _statusString,
                              };
    NSLog(@"did update reachability: %@", logInfo);
    [self _updateCommunicationStatusDescription];
}

- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didUpdateCarrierFromPreviousInfo:(nullable id<TNLCarrierInfo>)oldInfo
        toCurrentInfo:(nullable id<TNLCarrierInfo>)newInfo
{
    _carrierName = newInfo.carrierName ?: @"<null>";

    NSDictionary *logInfo = @{
                              @"carrier_old" : oldInfo ?: (id)@"<null>",
                              @"carrier_new" : newInfo ?: (id)@"<null>",
                              };
    NSLog(@"did update carrier: %@", logInfo);
    [self _updateCommunicationStatusDescription];
}

- (void)tnl_communicationAgent:(TNLCommunicationAgent *)agent
        didUpdateWWANRadioAccessTechnologyFromPreviousTech:(nullable NSString *)oldTech
        toCurrentTech:(nullable NSString *)newTech
{
    _radioTech = [newTech stringByReplacingOccurrencesOfString:@"CTRadioAccessTechnology" withString:@""] ?: @"<null>";

    NSDictionary *logInfo = @{
                              @"radioTech_old" : oldTech ?: @"null",
                              @"radioTech_new" : newTech ?: @"null",
                              };
    NSLog(@"did update radio tech: %@", logInfo);
    [self _updateCommunicationStatusDescription];
}

- (void)_updateCommunicationStatusDescription
{
    _communicationStatusDescription = [NSString stringWithFormat:@"%@, %@, %@,\n%@", _radioTech, _carrierName, _statusString, _SCFlagsString];
    [[NSNotificationCenter defaultCenter] postNotificationName:TNLXCommunicationStatusUpdatedNotification
                                                        object:_commAgent
                                                      userInfo:@{ @"description" : _communicationStatusDescription }];
}

- (NSString *)communicationStatusDescription
{
    return _communicationStatusDescription;
}

@end

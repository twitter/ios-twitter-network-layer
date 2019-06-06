//
//  TwitterNetworkLayer.h
//  TwitterNetworkLayer
//
//  Created on 6/9/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#pragma Headers

#import <TwitterNetworkLayer/TNLAttemptMetaData.h>
#import <TwitterNetworkLayer/TNLAttemptMetrics.h>
#import <TwitterNetworkLayer/TNLAuthenticationChallengeHandler.h>
#import <TwitterNetworkLayer/TNLCommunicationAgent.h>
#import <TwitterNetworkLayer/TNLContentCoding.h>
#import <TwitterNetworkLayer/TNLError.h>
#import <TwitterNetworkLayer/TNLGlobalConfiguration.h>
#import <TwitterNetworkLayer/TNLHostSanitizer.h>
#import <TwitterNetworkLayer/TNLHTTP.h>
#import <TwitterNetworkLayer/TNLHTTPHeaderProvider.h>
#import <TwitterNetworkLayer/TNLHTTPRequest.h>
#import <TwitterNetworkLayer/TNLLogger.h>
#import <TwitterNetworkLayer/TNLLRUCache.h>
#import <TwitterNetworkLayer/TNLNetwork.h>
#import <TwitterNetworkLayer/TNLNetworkObserver.h>
#import <TwitterNetworkLayer/TNLParameterCollection.h>
#import <TwitterNetworkLayer/TNLPriority.h>
#import <TwitterNetworkLayer/TNLPseudoURLProtocol.h>
#import <TwitterNetworkLayer/TNLRequest+Utilities.h>
#import <TwitterNetworkLayer/TNLRequest.h>
#import <TwitterNetworkLayer/TNLRequestAuthorizer.h>
#import <TwitterNetworkLayer/TNLRequestConfiguration.h>
#import <TwitterNetworkLayer/TNLRequestDelegate.h>
#import <TwitterNetworkLayer/TNLRequestEventHandler.h>
#import <TwitterNetworkLayer/TNLRequestHydrater.h>
#import <TwitterNetworkLayer/TNLRequestOperation.h>
#import <TwitterNetworkLayer/TNLRequestOperationCancelSource.h>
#import <TwitterNetworkLayer/TNLRequestOperationQueue.h>
#import <TwitterNetworkLayer/TNLRequestOperationState.h>
#import <TwitterNetworkLayer/TNLRequestRedirecter.h>
#import <TwitterNetworkLayer/TNLRequestRetryPolicyConfiguration.h>
#import <TwitterNetworkLayer/TNLRequestRetryPolicyProvider.h>
#import <TwitterNetworkLayer/TNLResponse.h>
#import <TwitterNetworkLayer/TNLSafeOperation.h>
#import <TwitterNetworkLayer/TNLTemporaryFile.h>
#import <TwitterNetworkLayer/TNLTiming.h>
#import <TwitterNetworkLayer/TNLURLCoding.h>

#pragma Categories

#import <TwitterNetworkLayer/NSCachedURLResponse+TNLAdditions.h>
#import <TwitterNetworkLayer/NSCoder+TNLAdditions.h>
#import <TwitterNetworkLayer/NSDictionary+TNLAdditions.h>
#import <TwitterNetworkLayer/NSHTTPCookieStorage+TNLAdditions.h>
#import <TwitterNetworkLayer/NSNumber+TNLURLCoding.h>
#import <TwitterNetworkLayer/NSOperationQueue+TNLSafety.h>
#import <TwitterNetworkLayer/NSURL+TNLAdditions.h>
#import <TwitterNetworkLayer/NSURLCache+TNLAdditions.h>
#import <TwitterNetworkLayer/NSURLCredentialStorage+TNLAdditions.h>
#import <TwitterNetworkLayer/NSURLRequest+TNLAdditions.h>
#import <TwitterNetworkLayer/NSURLResponse+TNLAdditions.h>
#import <TwitterNetworkLayer/NSURLSessionConfiguration+TNLAdditions.h>
#import <TwitterNetworkLayer/NSURLSessionTaskMetrics+TNLAdditions.h>

#pragma TODO list

/*

 Twitter Network Layer TODO list

 - TNLURLSessionTaskOperation
    - Heuristically determine estimated time remaining on a request to optimize the "shouldCancelInternal:" method
        - if fewer than 1 KB remaining (download), don't cancel
        - if the estimated remaining duration is less than 3 seconds (arbitrary), don't cancel

 - TNLRequest
    - Add support for resumeable downloads (resumeData)

*/

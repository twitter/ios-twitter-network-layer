//
//  TNLNetworkObserver.h
//  TwitterNetworkLayer
//
//  Created on 6/11/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLAttemptMetrics.h>

NS_ASSUME_NONNULL_BEGIN

@class NSURLRequest;
@class TNLRequestOperation;
@class TNLResponse;
@class TNLResponseInfo;
@class TNLAttemptMetrics;
@protocol TNLRequest;

/**
 The protocol used for observing network behavior.
 */
@protocol TNLNetworkObserver <NSObject>

@optional

/**
 Callback when a `TNLRequestOperation` starts (not enqueues)

 @param op The operation that's starting
 */
- (void)tnl_requestOperationDidStart:(TNLRequestOperation *)op;

/**
 Callback when an underlying attempt starts

 @param op              The source `TNLRequestOperation`
 @param URLRequest      The `NSURLRequest` used in the attempt
 @param type            The `TNLAttemptType` of the attempt
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
      didStartAttemptRequest:(NSURLRequest *)URLRequest
                     metrics:(TNLAttemptMetrics *)metrics;

/**
 Callback once an underlying attempt of a `TNLRequestOperation` has completed

 @param op The source `TNLRequestOperation` for the attempt
 @param response The intermediate `TNLResponse` for the attempt
 @param disposition The disposition of the _response_ (`Completing`, `Redirecting` or `Retrying`)
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
        didCompleteAttemptWithIntermediateResponse:(TNLResponse *)response
        disposition:(TNLAttemptCompleteDisposition)disposition;

/**
 Callback once a `TNLRequestOperation` completes

 @param op The `TNLRequestOperation` that finished
 @param response The `TNLResponse` of the completed request
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TNLResponse *)response;

@end

NS_ASSUME_NONNULL_END

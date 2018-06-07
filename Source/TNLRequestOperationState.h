//
//  TNLRequestOperation.h
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Request operation state: values representing where the operation is in its progress to retrieve a response for a request.

 See `TNLRequestOperation`

 __Helpers__

     #define TNLRequestOperationStateIsFinal(state)     ((state) < 0)
     #define TNLRequestOperationStateIsActive(state)    ((state) > 0)
     FOUNDATION_EXTERN NSString *TNLRequestOperationStateToString(TNLRequestOperationState state);
 */
typedef NS_ENUM(NSInteger, TNLRequestOperationState) {
    /** Operation is idle.  It has not yet started. */
    TNLRequestOperationStateIdle = 0,

    /** The request is being prepare for a network connection */
    TNLRequestOperationStatePreparingRequest = 1,
    /** The network connection is being established */
    TNLRequestOperationStateStarting,
    /** The network connection is executing on the request */
    TNLRequestOperationStateRunning,
    /** The operation has decided to retry and is waiting to do so */
    TNLRequestOperationStateWaitingToRetry,

    /** The operation was cancelled.  The _response.error_ will be populated with the cancellation error. */
    TNLRequestOperationStateCancelled = -1,
    /** The operation failed.  The _response.error_ will be populated with the error encountered. */
    TNLRequestOperationStateFailed = -2,
    /** The operation succeeded.  The _response.info.URLResponse_ will be populated and any other related response information. */
    TNLRequestOperationStateSucceeded = -100,
};

#define TNLRequestOperationStateIsFinal(state)     ((state) < 0)
#define TNLRequestOperationStateIsActive(state)    ((state) > 0)

//! Convert `TNLRequestOperationState` into a string suitable for logging
FOUNDATION_EXTERN NSString * __nullable TNLRequestOperationStateToString(TNLRequestOperationState state);

NS_ASSUME_NONNULL_END

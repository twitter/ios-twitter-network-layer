//
//  TNLRequestDelegate.h
//  TwitterNetworkLayer
//
//  Created on 11/20/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TNLAuthenticationChallengeHandler.h>
#import <TwitterNetworkLayer/TNLRequestAuthorizer.h>
#import <TwitterNetworkLayer/TNLRequestEventHandler.h>
#import <TwitterNetworkLayer/TNLRequestHydrater.h>
#import <TwitterNetworkLayer/TNLRequestRedirecter.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The delegate for the `TNLRequestOperation` to use while executing on a `TNLRequest`.

 __See also:__ `TNLRequestOperation`, `TNLRequestOperationQueue` and `TNLRequestConfiguration`
 */
@protocol TNLRequestDelegate <TNLRequestAuthorizer, TNLRequestEventHandler, TNLRequestHydrater, TNLRequestRedirecter, TNLRequestAuthenticationChallengeHandler>

@optional

/**
 The `dispatch_queue_t` to use for all delegate callbacks, except the completion callback.
 If any delegate requires independent threading from the other delegate objects,
 it should dispatch_async to the queue of its choosing since the `delegeteQueue` is shared between
 all delegate objects.

 Default is `NULL`, which will result in an internal background queue being used
 */
- (nullable dispatch_queue_t)tnl_delegateQueueForRequestOperation:(TNLRequestOperation *)op;

/**
 The `dispatch_queue_t` to use for the completion callback:
 `[TNLRequestEventHandler tnl_requestOperation:didCompleteWithResponse:]` or `TNLRequestDidCompleteBlock`.

 Default is `NULL`, which will result in the main queue being used.
 */
- (nullable dispatch_queue_t)tnl_completionQueueForRequestOperation:(TNLRequestOperation *)op;

@end

NS_ASSUME_NONNULL_END

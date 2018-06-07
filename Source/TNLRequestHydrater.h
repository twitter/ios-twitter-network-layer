//
//  TNLRequestHydrater.h
//  TwitterNetworkLayer
//
//  Created on 8/14/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLRequestOperation;
@protocol TNLRequest;

//! completion block for `TNLRequestHydrater` callback
typedef void(^TNLRequestHydrateCompletionBlock)(id<TNLRequest> __nullable hydratedRequest,
                                                NSError * __nullable error);

/**
 The delegate protocol that hydrates `TNLRequest`s.

 If the `TNLRequestHydrater` requires independent threading from the other delegate objects,
 it should dispatch_async to the queue of its choosing since the
 `[TNLRequestDelegate tnl_delegateQueueForRequestOperation:]` is shared between all delegate objects.
 */
@protocol TNLRequestHydrater <NSObject>

@optional

/**
 Create a hydrated request object conforming to `TNLRequest` (optional)

 By default, `[request copy]` will be used as the hydrated request if the _request_ conforms to
 `NSCopying`.  If _request_ doesn't conform to `NSCopying`, the hydrated request will be used itself.
 If the request doesn't conform to `TNLRequest` (such as the original request being only a `TNLRequest`),
 the operation with fail with an error.

 This callback is executed from `[TNLRequestDelegate delegateQueue]` if defined, or an internal
 background queue if not defined.

 __TNLRequestHydrateCompletionBlock__

     typedef void(^TNLRequestHydrateCompletionBlock)(id<<TNLRequest>> hydratedRequest, NSError *error);

 - _hydratedRequest_
   - The hydrated request conforming to `TNLRequest`
   - Can be the source _request_
   - Can be `nil`, effectively the same as passing in the source _request_
   - If the _hydratedRequest_ does not pass the `[TNLRequest validateRequest:againstConfiguration:error:]` test the request operation will fail (obviously)
 - _error_
   - The `NSError` if the _request_ could not be hydrated or `nil`
   - _hydratedRequest_ will be ignored if _error_ is not `nil`

 @param op       the `TNLRequestOperation` querying for the hydrated request
 @param request  the request to hydrate.  `op.originalRequest == request`
 @param complete the completion block to call with the hydrated request or error
 */
- (void)tnl_requestOperation:(TNLRequestOperation *)op
              hydrateRequest:(id<TNLRequest>)request
                  completion:(TNLRequestHydrateCompletionBlock)complete;

@end

NS_ASSUME_NONNULL_END

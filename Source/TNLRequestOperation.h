//
//  TNLRequestOperation.h
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <TwitterNetworkLayer/TNLPriority.h>
#import <TwitterNetworkLayer/TNLRequestEventHandler.h>
#import <TwitterNetworkLayer/TNLRequestOperationState.h>
#import <TwitterNetworkLayer/TNLSafeOperation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TNLRequest;
@protocol TNLRequestDelegate;
@protocol TNLRequestOperationCancelSource;
@class TNLRequestOperation;
@class TNLResponse;
@class TNLRequestOperationQueue;
@class TNLRequestConfiguration;

//! completion block for `TNLRequestOperation` instances that use a block instead of a delegate
typedef void(^TNLRequestDidCompleteBlock)(TNLRequestOperation *op, TNLResponse *response);

/**
 The request operation that owns the process of turning a `TNLRequest` into a `TNLResponse`.

 The `TNLRequestOperation`s can only be enqueued to `TNLRequestOperationQueue`s.

 The creation of a `TNLRequestOperation` is done by providing several objects that are necessary for
 the `TNLRequestOperation` to operate to a constructor.

 1. an object adopting the `TNLRequest` protocol
   - The object is copied and maintained (immutably) as the _originalRequest_
   - The object can, optionally, be hydrated with a `TNLRequestHydrater`
     - Not hydrating will use the _originalRequest_ as the _hydratedRequest_
   - The hydrated `TNLRequest` object will be used in the underlying `NSURL` by populating an `NSURLRequest` for use in the network connection
     - `NSURLRequest` implicitely adopts the `TNLRequest` protocol and can be used in APIs requiring an object adopting the `TNLRequest` protocol.
     - `NSURLRequest` also explicitly adopts the `TNLRequest` protocol thanks to a category in _TNLRequest.h_ `NSURLRequest(TNLExtensions)`)
   - __The hydrated request represents _WHAT_ is to be requested over the network.__
 2. a `TNLRequestConfiguration`
   - The configuration provided (which could be `nil` and therefor will fallback to `[TNLRequestConfiguration defaultConfiguration]`).
   - __The configuration is used to configure _HOW_ the request should be requested over the network.__
 3. a `TNLRequestDelegate`
   - The delegate (which could be `nil`).
   - __The delegate is used for 2 things:__
     1. to delegate how to behave while executing upon the given request
     2. to delegate the events that the operation elicits through the course of the request being used to generate a response.

 __NSOperation__

 `TNLRequestOperation` is a subclass of `NSOperation` and nearly all APIs related to `NSOperation`
 are supported by `TNLRequestOperation`.  That includes:

  - setting up dependencies
  - setting priority
  - setting a completion block
  - setting a _name_ (iOS 8+)
  - using `waitUntilFinished`
  - using `cancel`

 One feature not supported by `TNLRequestOperation` is enqueing the operation to any
 `NSOperationQueue`, a `TNLRequestOperationQueue` must be used.

 @warning Don't modify an NSOperation after it has been enqueued per Apple documentation:
 https://developer.apple.com/library/mac/documentation/General/Conceptual/ConcurrencyProgrammingGuide/OperationObjects/OperationObjects.html

 > __Important:__ Never modify an operation object after it has been added to a queue.
 While waiting in a queue, the operation could start executing at any time, so changing its
 dependencies or the data it contains could have adverse effects.
 If you want to know the status of an operation, you can use the methods of the `NSOperation` class to
 determine if the operation is running, waiting to run, or already finished.
 */
@interface TNLRequestOperation : TNLSafeOperation

/** Randomly generated operationId that will be the same for all attempts of this request operation */
@property (nonatomic, readonly) int64_t operationId;

/** The `TNLRequestOperationQueue` that owns this operation.  Set once the operation is enqueued. */
@property (nonatomic, readonly, nullable) TNLRequestOperationQueue *requestOperationQueue;
/** The `TNLRequestConfiguration` for this request operation */
@property (nonatomic, readonly) TNLRequestConfiguration *requestConfiguration;
/** The `TNLRequestDelegate` for this request operation */
@property (nonatomic, readonly, weak, nullable) id<TNLRequestDelegate> requestDelegate;

/** The original `TNLRequest` for this operation */
@property (nonatomic, readonly, nullable) id<TNLRequest> originalRequest;
/** The hydrated `TNLRequest` for this operation, see `TNLRequestHydrater` */
@property (nonatomic, readonly, nullable) id<TNLRequest> hydratedRequest;

/** The `Class` of the response */
@property (readonly) Class responseClass;
/** The `TNLResponse` this request operation produced (populated at completion). */
@property (readonly, nullable) TNLResponse *response;
/**
 Any error that has occurred during the processing of this operation.
 This error will end up being used to populate _response.operationError_. See `TNLRequestEventHandler`
 */
@property (readonly, nullable) NSError *error;

/** The current `TNLRequestOperationState` of the request operation.  See `TNLRequestEventHandler`. */
@property (nonatomic, readonly) TNLRequestOperationState state;

/** The number of times the operation has started a URL request attempt.  See also: `TNLRequestRetryPolicyProvider` and `TNLRequestEventHandler` */
@property (nonatomic, readonly) NSUInteger attemptCount;
/** The number of times the operation was retried from it's `originalRequest`.  See `TNLRequestRetryPolicyProvider`. */
@property (nonatomic, readonly) NSUInteger retryCount;
/** The number of times the operation was redirected.  See `TNLRequestRedirectPolicy`.  */
@property (nonatomic, readonly) NSUInteger redirectCount;

/**
 The download progress of the request operation. See `TNLRequestEventHandler`
 @note for instances when more data is downloaded than was expected, the progress will be capped to `1.0f` until completion
 */
@property (nonatomic, readonly) float downloadProgress;
/**
 The upload progress of the request operation. See `TNLRequestEventHandler`
 @note for instances when more data is downloaded than was expected, the progress will be capped to `1.0f` until completion
 */
@property (nonatomic, readonly) float uploadProgress;

/**
 Any additional context desired to be set with the operation.
 */
@property (nonatomic, nullable) id context;

/**
 The priority of the operation.
 Carries through the _QoS_, _queue priority_ and _protocol priority_ (aka _SPDY_ or _HTTP/2_ priority).

 Can be updated dynamically (a.k.a. after the operation has already started),
 but dynamic updates only apply to the _protocol priority_ (if supported by the underlying protocol).

 Default is `TNLPriorityNormal`
 */
@property (atomic) TNLPriority priority;


/**
 Create a new operation for later enqueuing to a `TNLRequestOperationQueue`

 @param request         The request to start the operation with
 @param responseClass   The desired class for the response.  MUST be `Nil` or a subclass of `TNLResponse`.  Default is `TNLResponse`.
 @param config      The configuration for the operation, can be `nil` (when `nil` will fallback to `[TNLRequestConfiguration defaultConfiguration]`).
 @param delegate    The *weakly held delegate* for the operation, can be `nil`.
 @return A new operation
 */
+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       responseClass:(nullable Class)responseClass
                       configuration:(nullable TNLRequestConfiguration *)config
                            delegate:(nullable id<TNLRequestDelegate>)delegate;


/**
 Cancel the operation

 Cancel will force the operation to fail (if it hasn't yet completed) and will result in the
 completion callback `[TNLRequestEventHandler tnl_requestOperation:didCompleteWithResponse:]` being called.

 The error on completion will be a `TNLErrorDomain` _domain_ error with
 `TNLErrorCodeRequestOperationCancelled` as the _code_.
 It will also have `TNLErrorCancelSourceKey`, `TNLErrorCancelSourceDescriptionKey` and
 (optionally) `TNLErrorCancelSourceLocalizedDescriptionKey` populated in the _userInfo_ and
 (optionally) the _optionalUnderlyingError_ set as the `NSUnderlyingError` in the _userInfo_.
 See `TNLErrorCode`

 See `TNLRequestOperationCancelSource` for more details.

 @param source The (required) value to set in resulting `TNLResponse` object's _error.userInfo_ for
 the `TNLErrorCancelSourceKey` key and is the provider of the `TNLErrorCancelSourceDescriptionKey`
 and (optionally) `TNLErrorCancelSourceLocalizedDescriptionKey` values
 @param optionalUnderlyingError The (optional) value to set in resulting `TNLResponse` object's
 _error.userInfo_ for the `NSUnderlyingError` key
 */
- (void)cancelWithSource:(id<TNLRequestOperationCancelSource>)source
         underlyingError:(nullable NSError *)optionalUnderlyingError;
/**
 Cancel the operation.

 Calls `cancelWithSource:underlyingError:` with `nil` for the _optionalUnderlyingError_
 */
- (void)cancelWithSource:(id<TNLRequestOperationCancelSource>)source;
/**
 Cancel the operation.  See `NSOperation`

 Calls `cancelWithSource:` and provides a `TNLOperationCancelMethodCancelSource` for the _source_
 @warning Deprecated: use `cancelWithSource:` or `cancelWithSource:underlyingError:` instead.
 */
- (void)cancel __attribute__((deprecated("do not use 'cancel' directly.  Call 'cancelWithSource:' or cancelWithSource:underlyingError:' instead")));

/**
 Wait for the operation to finish.  See `[NSOperation waitUntilFinished]`.
 @warning This blocks on a semaphore so the thread will be completely blocked.
 To wait without blocking the thread by pumping the runloop, use `waitUntilFinishedWithoutBlockingRunLoop`
 */
- (void)waitUntilFinished;

/**
 Since `waitUntilFinished` is prone to deadlocks with a heavily asynchronous system like __TNL__,
 `waitUntilFinishedWithoutBlockingRunLoop` is provided so that the run loop can be pumped while
 waiting for the operation to finish (be sure there are sources to pump when using this method).
 */
- (void)waitUntilFinishedWithoutBlockingRunLoop;

@end

/**
 @discussion __TNLRequestOperation (NSURLExposure)__

 the underlying `NSURL` objects used during the operation, exposed for convenience.
 */
@interface TNLRequestOperation (NSURLExposure)

/** The original `NSURLRequest` generated from the _hydratedRequest_ */
@property (readonly, nullable) NSURLRequest *hydratedURLRequest;
/** The current `NSURLRequest` (starting as being the same as _hydratedURLRequest_) that changes as network redirects are encountered and followed */
@property (readonly, nullable) NSURLRequest *currentURLRequest;
/** The current `NSURLResponse` for the operation */
@property (readonly, nullable) NSHTTPURLResponse *currentURLResponse;

@end

@interface TNLRequestOperation (Unavailable)

/** Unavailable */
- (instancetype)init NS_UNAVAILABLE;
/** Unavailable */
+ (instancetype)new NS_UNAVAILABLE;

/** Unavailable */
- (void)setQualityOfService:(NSQualityOfService)qualityOfService NS_UNAVAILABLE;
/** Unavailable */
- (void)setThreadPriority:(double)threadPriority NS_UNAVAILABLE;
/** Unavailable */
- (void)setQueuePriority:(NSOperationQueuePriority)queuePriority NS_UNAVAILABLE;

@end

/**
 __TNLRequestOperation (Convenience)__

 Convenience methods for creating new `TNLRequestOperation` objects.

 See also: `TNLRequest`, `NSURL`, `TNLRequestConfiguration` and `TNLRequestDelegate`
 */
@interface TNLRequestOperation (Convenience)

/**
 Create a new operation for later enqueuing to a `TNLRequestOperationQueue`

 @param request The request to start the operation with
 @param config The configuration for the operation, can be `nil`
 (when `nil` will fallback to `[TNLRequestConfiguration defaultConfiguration]`).
 @param delegate The *weakly held delegate* for the operation, can be `nil`.
 @return A new operation
 */
+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       configuration:(nullable TNLRequestConfiguration *)config
                            delegate:(nullable id<TNLRequestDelegate>)delegate;

/**
 Same as calling `operationWithRequest:configuration:delegate:` with `[NRURLRequest requestWithURL:url]` as the _request_
 */
+ (instancetype)operationWithURL:(nullable NSURL *)url
                   configuration:(nullable TNLRequestConfiguration *)config
                        delegate:(nullable id<TNLRequestDelegate>)delegate;

/**
 Convenience constructor that doesn't need a `TNLRequestConfiguration` nor a `TNLRequestDelegate`

 @note `TNLRequestOperation(Convenience)` constructors will not be able to have the full set of
 features available to `TNLRequestOperation`.
 See `[TNLRequestOperation operationWithRequest:configuration:delegate:]`.

 @param request    the `TNLRequest` conforming request to execute upon
 @param completion the `TNLRequestDidCompleteBlock` completion block.  See `TNLRequestEventHandler` concrete class.

 @return the `TNLRequestOperation` to schedule.  See `[TNLRequestOperationQueue enqueueRequestOperation:]`.
 */
+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                          completion:(nullable TNLRequestDidCompleteBlock)completion;

/**
 Convenience constructor that doesn't need a `TNLRequestDelegate`

 @note `TNLRequestOperation(Convenience)` constructors will not be able to have the full set of
 features available to `TNLRequestOperation`.
 See `[TNLRequestOperation operationWithRequest:configuration:delegate:]`.

 @param request    the `TNLRequest` conforming request to execute upon
 @param config     the configuration for the operation, can be `nil` (when `nil` will fallback to `[TNLRequestConfiguration defaultConfiguration]`).
 @param completion the `TNLRequestDidCompleteBlock` completion block.  See `TNLRequestEventHandler` concrete class.

 @return the `TNLRequestOperation` to schedule.  See `[TNLRequestOperationQueue enqueueRequestOperation:]`.
 */
+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       configuration:(nullable TNLRequestConfiguration *)config
                          completion:(nullable TNLRequestDidCompleteBlock)completion;

/**
 Convenience constructor that doesn't need a `TNLRequestDelegate`

 @note `TNLRequestOperation(Convenience)` constructors will not be able to have the full set of
 features available to `TNLRequestOperation`.
 See `[TNLRequestOperation operationWithRequest:configuration:delegate:]`.

 @param request         the `TNLRequest` conforming request to execute upon
 @param responseClass   the `TNLRequest` subclass for the response.  `Nil` will fall back to `TNLResponse`.
 @param config          the configuration for the operation, can be `nil` (when `nil` will fallback to `[TNLRequestConfiguration defaultConfiguration]`).
 @param completion      the `TNLRequestDidCompleteBlock` completion block.  See `TNLRequestEventHandler` concrete class.

 @return the `TNLRequestOperation` to schedule.  See `[TNLRequestOperationQueue enqueueRequestOperation:]`.
 */
+ (instancetype)operationWithRequest:(nullable id<TNLRequest>)request
                       responseClass:(nullable Class)responseClass
                       configuration:(nullable TNLRequestConfiguration *)config
                          completion:(nullable TNLRequestDidCompleteBlock)completion;

/**
 Same as `[TNLRequestOperation operationWithRequest:completion:]` with _request_ being
 `[NSURLRequest requestWithURL:`_url_`]`
 */
+ (instancetype)operationWithURL:(nullable NSURL *)url
                      completion:(nullable TNLRequestDidCompleteBlock)completion;

@end

NS_ASSUME_NONNULL_END

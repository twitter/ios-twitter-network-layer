//
//  TNLRequestOperationQueue.h
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <TwitterNetworkLayer/TNLRequestOperation.h>

@protocol TNLNetworkObserver;

NS_ASSUME_NONNULL_BEGIN

// Background request notification and key constants

FOUNDATION_EXTERN NSString * const TNLBackgroundRequestOperationDidCompleteNotification;
FOUNDATION_EXTERN NSString * const TNLBackgroundRequestURLRequestKey;                          // NSURLRequest
FOUNDATION_EXTERN NSString * const TNLBackgroundRequestResponseKey;                            // TNLResponse
FOUNDATION_EXTERN NSString * const TNLBackgroundRequestURLSessionConfigurationIdentifierKey;   // NSString
FOUNDATION_EXTERN NSString * const TNLBackgroundRequestURLSessionTaskIdentifierKey;            // @(NSUInteger)
FOUNDATION_EXTERN NSString * const TNLBackgroundRequestURLSessionSharedContainerIdentifierKey; // NSString

/**
 The `TNLRequestOperationQueue` is the core flow control object of __TNL__

 ## TNLRequestOperationQueue Responsibility

 The operation queue is primarily responsible for flow control:

 - see `[TNLRequestOperationQueue enqueueRequestOperation:]`
 - The features `TNLRequestOperationQueue` provides regarding enqueing are:
   - Queue prioritization
   - Automatic notifications regarding running network connections
     - See `TNLNetworkExecutingNetworkConnectionsDidUpdateNotification`
     - See `[TNLNetwork incrementExecutingNetworkConnections]` and `[TNLNetwork decrementExecutingNetworkConnections]`
   - Eliciting informative callbacks to `TNLNetworkObserver`
   - Suspending

 ## High Level

 Effectively, the way you use a `TNLRequestOperationQueue` is fairly simple.

 1. Create your `TNLRequestOperationQueue` and persist it somehow (or use the `defaultOperationQueue`)
    - FWIW: Custom `TNLRequestOperationQueue` instances are rarely necessary.
 2. Get a `TNLRequestOperation` with a `TNLRequest` conforming object, a `TNLRequestConfiguration` (optional) and a `TNLRequestDelegate` (optional)
 3. (Optionally) customize your `TNLRequestOperation`'s properties (such as `[NSOperation dependencies]` and `[TNLRequestOperation priority]`
 3. Enqueue your `TNLRequestOperation`

 ## Background Requests

 __TNL__ supports executing requests in the background and as such needs a headless mechanism to
 support handling the completion of those requests.   __TNL__ uses an `NSNotification` pattern for
 notifying interested parties when a background request completes.

 - `TNLBackgroundRequestOperationDidCompleteNotification` which has some user info values
   - `TNLBackgroundRequestURLRequestKey`
     - the `NSURLRequest` of the background request that completed
   - `TNLBackgroundRequestResponseKey`
     - the `TNLResponse` encapsulting the result of the request
   - `TNLBackgroundRequestURLSessionConfigurationIdentifierKey`
     - The `NSURLSessionConfiguration`'s _identifier_ as an `NSString`
   - `TNLBackgroundRequestURLSessionTaskIdentifierKey`
     - An unsigned integer (wrapped in an `NSNumber`) that matches the _taskIdentifier_ of the underlying `NSURLSessionTask` that completed
   - `TNLBackgroundRequestURLSessionSharedContainerIdentifierKey` (iOS 8+ only)
     - The `NSString` _sharedContainerIdentifier_ of the `NSURLSessionConfiguration`
 - __TODO:[nobrien]__ - Change this from specifically being a _background_ request notification to a _headless_ request notification.

 ## TNLRequestOperationQueue categories
 */
@interface TNLRequestOperationQueue : NSObject

/**
 The default singleton instance of a `TNLRequestOperationQueue`.
 Easiest option for just sending a request.
 */
+ (instancetype)defaultOperationQueue;

/**
 Default initializer

 @param identifier The identifier to use for identifying this specific `TNLRequestOperationQueue`.
 This identifier MUST be unique among all running queues.  Must be in URL host form.
 Any _identifier_ that is not ASCII alpha-numeric with optional `'.'` seperators, is `nil` or is zero _length_
 will throw an exception. If an existing`TNLRequestOperationQueue` already has the given identifier,
 an exception will be thrown.

 @return A new instance of a `TNLRequestOperationQueue`
 */
- (instancetype)initWithIdentifier:(NSString *)identifier NS_DESIGNATED_INITIALIZER;

/** 'NS_UNAVAILABLE' */
- (instancetype)init NS_UNAVAILABLE;
/** 'NS_UNAVAILABLE' */
+ (instancetype)new NS_UNAVAILABLE;

/** The (preferrably unique) identifier for receiver */
@property (nonatomic, readonly, copy) NSString *identifier;

/** The delegate `TNLNetworkObserver` to receive callbacks related to operations that enqueue with the receiver. */
@property (atomic, nullable) id<TNLNetworkObserver> networkObserver;



/**
 Increment the __suspend count__

 A `0` __suspend count__ will permit the receiver to execute enqueued requests.
 Any other __suspend count__ will suspend the receiver.

 Suspension won't actually pause executing operations, just prevent queued operations from executing.

 @note `defaultOperationQueue` cannot be suspended
 */
- (void)suspend;

/**
 Decrement the __suspend count__
 @discussion See `suspend`
 */
- (void)resume;


/**
 Core enqueue method.
 @warning Never modify an operation object after it has been added to a queue.  See `TNLRequestOperation`
 @param op the `TNLRequestOperation` to enqueue
 @note Providing `nil` will result in an exception.
 Providing an opertion that has already been enqueued to a `TNLRequestOperationQueue` will result in an exception.
 */
- (void)enqueueRequestOperation:(TNLRequestOperation *)op;

/**
 Convenience enqueue method for very simple requests.
 @param request the `TNLRequest` to enqueue
 @param completion the completion block
 @return Returns the `TNLRequestOperation` that was enqueued
 See `enqueueRequestOperation:`
 */
- (TNLRequestOperation *)enqueueRequest:(nullable id<TNLRequest>)request
                             completion:(nullable TNLRequestDidCompleteBlock)completion;

/**
 Cancel all enqueued operations

 Cancel will force the operations to fail (if they haven't yet completed) and will result in the
 completion callback `[TNLRequestEventHandler tnl_requestOperation:didCompleteWithResponse:]` being called.

 The error(s) on completion will be a `TNLErrorDomain` _domain_ error with
 `TNLErrorCodeRequestOperationCancelled` as the _code_.  It will also have `TNLErrorCancelSourceKey`
 and `TNLErrorCancelSourceDescriptionKey` populated in the _userInfo_ and (optionally) the
 _optionalUnderlyingError_ set as the `NSUnderlyingError` in the _userInfo_.
 See `TNLErrorCode`

 @param source The (required) value to set in resulting `TNLResponse` object's _error.userInfo_ for
 the `TNLErrorCancelSourceKey` key and is the provider of the `TNLErrorCancelSourceDescriptionKey` value
 @param optionalUnderlyingError The (optional) value to set in resulting `TNLResponse` object's
 _error.userInfo_ for the `NSUnderlyingError` key

 See also: `[TNLRequestOperation cancelWithSource:underlyingError:]`
 */
- (void)cancelAllWithSource:(id<TNLRequestOperationCancelSource>)source
            underlyingError:(nullable NSError *)optionalUnderlyingError;

/**
 Cancel the operation.

 Calls `cancelAllWithSource:underlyingError:` with `nil` for the _optionalUnderlyingError_
 */
- (void)cancelAllWithSource:(id<TNLRequestOperationCancelSource>)source;

@end

#if TARGET_OS_IPHONE // == IOS + WATCH + TV
/**
 __TNLRequestOperationQueue (Background)__

 Class method for handling a background `NSURLSession` completing their events when the app wasn't running
 */
@interface TNLRequestOperationQueue (Background)

#pragma twitter startignorestylecheck
/**
 The class method used for handling a background `NSURLSession` competing their events when the app wasn't running

 Have your `UIApplicationDelegate` implement
 `application:handleEventsForBackgroundURLSession:completionHandler:` and in that handler call this
 method for handling the background events via __TNL__.  For best results, be sure your reusable
 `TNLRequestOperationQueue`s are all configured properly before calling this method.

 __Example:__

      - (void)application:(UIApplication *)application
              handleEventsForBackgroundURLSession:(NSString *)identifier
              completionHandler:(dispatch_block_t)completionHandler
      {
          [self ensureRequestOperationQueuesAreConfigured]; // optional

          if (![TNLRequestOperationQueue handleBackgroundURLSessionEvents:identifier
                                                        completionHandler:completionHandler]) {
              BOOL handled = NO;

              // ...
              // Custom work
              // ...

              if (!handled) {
                  completionHandler();
              }
          }
      }

 @param identifier        The `NSURLSessionConfigurationIdentifier` of the background `NSURLSession` to handle
 @param completionHandler The completionHandler needed to call when the background `NSURLSession` has completed its events

 @return `YES` if the events will be handled, `NO` if the events won't be handled by __TNL__
 */
+ (BOOL)handleBackgroundURLSessionEvents:(nullable NSString *)identifier
                       completionHandler:(dispatch_block_t)completionHandler;
#pragma twitter endignorestylecheck

@end
#endif

NS_ASSUME_NONNULL_END

//
//  TNLRequestOperationCancelSource.h
//  TwitterNetworkLayer
//
//  Created on 10/21/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 TNLRequestOperationCancelSource protocol

 Protocol for specifying the source of what cancelled a `TNLRequestOperation`.

 The purpose of requiring all cancellations of `TNLRequestOperation`s to provide a _cancel source_
 is that it provides valuable context as to the reason for the cancellation.  By being a protocol,
 it opens up the possibilities for what context a consumer of __TNL__ can provide to be anything.
 The simplest option is to just provide a descriptive `NSString`.

 The value of the _cancel source_ is entirely dependent on how much context the consumer of __TNL__
 chooses to supply.  For example: providing `@"Cancelled"` as the _cancel source_ is valid,
 but offers pretty much no insight into why the operation was cancelled.
 However, providing even just slightly more context like `@"User Navigated Away"` or
 `@"Reissuing Request"` or `@"Dependency No Longer Available"` provide much more value in
 understanding the reason for the cancellation.

 For `TNLRequestOperation`s that are directly tied to user interaction, a localized description may
 prove useful so that the cancellation can be surfaced to the user via UI, such as:
 `@"We can no longer send your message since you have been logged out.  Please log back in and try again."`

 See also `NSString(TNLRequestOperationCancelSource)` and `TNLOperationCancelMethodCancelSource`
 */
@protocol TNLRequestOperationCancelSource <NSObject>

@required
/**
 A description of what cancelled the `TNLRequestOperation`.
 This string is not user facing and should not be localized.
 @return a string, cannot be `nil`
 */
- (NSString *)tnl_cancelSourceDescription;

@optional
/**
 A localized description that can be presented to users for what cancelled the `TNLRequestOperation`.
 @return a string, `nil` value will be ignored
 */
- (nullable NSString *)tnl_localizedCancelSourceDescription;

/**
 An overriding error in the case that the "cancel" should not be treated with a `TNLErrorCodeRequestOperationCancelled` error.
 @return an `NSError`, `nil` value will continue to treat the cancel source as a `TNLErrorCodeRequestOperationCancelled` error source.
 */
- (nullable NSError *)tnl_cancelSourceOverrideError;

@end

/**
 Category on NSString to adopt `TNLRequestOperationCancelSource` as a convenience.
 */
@interface NSString (TNLRequestOperationCancelSource) <TNLRequestOperationCancelSource>
/** returns `self` */
- (NSString *)tnl_cancelSourceDescription;
@end

/**
 Category on NSError to adopt `TNLRequestOperationCancelSource` as a convenience.
 */
@interface NSError (TNLRequestOperationCancelSource) <TNLRequestOperationCancelSource>
/** returns `[self description]` */
- (NSString *)tnl_cancelSourceDescription;
/** returns `self` */
- (NSString *)tnl_cancelSourceOverrideError;
@end

/**
 This class will represent the `TNLRequestOperationCancelSource` of a `TNLRequestOperation` when the
 `NSOperation` superclass' `cancel` method is invoked.
 */
@interface TNLOperationCancelMethodCancelSource : NSObject <TNLRequestOperationCancelSource>
@end

NS_ASSUME_NONNULL_END

//
//  TNLHostSanitizer.h
//  TwitterNetworkLayer
//
//  Created on 11/21/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** The behavior for how to sanitize the request based on its host */
typedef NS_ENUM(NSInteger, TNLHostSanitizerBehavior) {

    // No-op Behaviors

    /** Do nothing, leave the host alone */
    TNLHostSanitizerBehaviorNone = 0,

    // Modification Behaviors

    /**
     Replace the host with a different host.
     This will also override `"Host"` in HTTP Header Field to match
     the host that was sanitized instead of the OS default behavior of
     using the sanitized host.
     @note If `"Host"` is already overridden in the request, it will not be overridden.
     */
    TNLHostSanitizerBehaviorChange = 1,

    /**
     Replace the host with a different host.
     This will not modify the `"Host"` HTTP Header Field.
     */
    TNLHostSanitizerBehaviorChangeWithoutModifyingHTTPHeaderField = 2,

    // Failure Behaviors

    /** Block the host (results in an error on the response) */
    TNLHostSanitizerBehaviorBlock = -1,
};

#define TNLHostSanitizerBehaviorIsModification(behavior) ((behavior) > 0)
#define TNLHostSanitizerBehaviorIsFailure(behavior)      ((behavior) < 0)
#define TNLHostSanitizerBehaviorIsNone(behavior)         ((behavior) == 0)

/** result enum for sanitizing/modifying a host */
typedef NS_ENUM(NSInteger, TNLHostReplacementResult) {
    /** failure in replacing host */
    TNLHostReplacementResultFail = 0,
    /** succeeded in replacing host */
    TNLHostReplacementResultSuccess = 1,
    /** noop, there was nothing to do */
    TNLHostReplacementResultNoop = 100,
};

//! completion block for `TNLHostSanitizer` callback
typedef void(^TNLHostSanitizerCompletionBlock)(TNLHostSanitizerBehavior behavior, NSString * __nullable newHost);

/**
 `TNLHostSanitizer` is the procotol for a global object to implement for sanitizing the host of each and every `TNLRequestOperation`.

 ## Completion Block

     typedef void(^TNLHostSanitizerCompletionBlock)(TNLHostSanitizerBehavior behavior, NSString *newHost);

 Provide the _behavior_ and, if that behavior modifies the host, also provide a _newHost_.

 */
@protocol TNLHostSanitizer <NSObject>
@required
/**
 Call back for the sanitizer to implement to determine the sanitization behavior on the given _host_.

 @param host            the URL host to sanitize
 @param request         the `NSURLRequest` the host came from
 @param redirect        whether the request is from a redirect or not
 @param completionBlock the completion block to execute.
 _behavior_ will indicate how to sanitize the host and _host_ is ignored unless _behavior_ is to
 modify the _host_, then _newHost_ needs to be a valid URL host.
 Providing `TNLHostSanitizerBehaviorBlock` will cause the request to fail and the `TNLResponse` instance's
 `error` to be populated with a `TNLErrorCodeGlobalHostWasBlocked` `code`.
 */
- (void)tnl_host:(NSString *)host
        wasEncounteredForURLRequest:(NSURLRequest *)request
        asRedirect:(BOOL)redirect
        completion:(TNLHostSanitizerCompletionBlock)completionBlock;
@end

NS_ASSUME_NONNULL_END

//
//  TNLAuthenticationChallengeHandler.h
//  TwitterNetworkLayer
//
//  Created on 4/10/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLRequestOperation;

typedef void(^TNLURLSessionAuthChallengeCompletionBlock)(NSURLSessionAuthChallengeDisposition disposition,
                                                         id __nullable credentialOrCancelContext);

/**
 Protocol for handling authentication challenges
 */
@protocol TNLAuthenticationChallengeHandler <NSObject>

@optional

/**
 Handle an authentication challenge (optional)

 By default, the _challenge_ is handled with `NSURLSessionAuthChallengePerformDefaultHandling`
 _disposition_ and `nil` _credential_.  This callback is executed from an internal background queue.

 __TNLURLSessionAuthChallengeCompletionBlock__

 See `NSURLSessionAuthChallengeDisposition`

    typedef void(^TNLURLSessionAuthChallengeCompletionBlock)(NSURLSessionAuthChallengeDisposition disposition, id credentialOrCancelContext);

 - _disposition_
   - the way to handle the _challenge_ (default == `NSURLSessionAuthChallengePerformDefaultHandling`)
 - _credentialOrCancelContext_
   - the credential to use in handling the _challenge_ for `NSURLSessionAuthChallengeUseCredential`
   - the context to the error that will be yielded from `NSURLSessionAuthChallengeCancelAuthenticationChallenge` (using

 @param challenge  The `NSURLAuthenticationChallenge` to respond to
 @param op The `TNLRequestOperation` that triggered the challenge, `nil` is a global challenge
 @param completion The completion block to call after finishing the handling of the _challenge_

 @warning This method is called from the underlying socket thread and calling completion
 synchronously is __STRONGLY RECOMMENDED__.  There can be threading issues with Apple's networking
 stack if not done synchronously which will result in crashes.
 */
- (void)tnl_networkLayerDidReceiveAuthChallenge:(NSURLAuthenticationChallenge *)challenge
                               requestOperation:(nullable TNLRequestOperation *)op
                                     completion:(TNLURLSessionAuthChallengeCompletionBlock)completion;

@end

/**
 Same interface as `TNLAuthenticationChallengeHandler` for `TNLRequestDelegate` to conform to
 */
@protocol TNLRequestAuthenticationChallengeHandler <TNLAuthenticationChallengeHandler>
@optional
/** See `TNLAuthenticationChallengeHandler` */
- (void)tnl_networkLayerDidReceiveAuthChallenge:(NSURLAuthenticationChallenge *)challenge
                               requestOperation:(nonnull TNLRequestOperation *)op
                                     completion:(TNLURLSessionAuthChallengeCompletionBlock)completion;
@end

NS_ASSUME_NONNULL_END

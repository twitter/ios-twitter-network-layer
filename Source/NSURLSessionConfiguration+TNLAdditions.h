//
//  NSURLSessionConfiguration+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 8/12/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURLSessionConfiguration`
 */
@interface NSURLSessionConfiguration (TNLAdditions)

/**
 Returns `NO` if transaction metrics cannot be used.
 Task Metrics were introduced in iOS 10 / macOS 10.12.
 There was a crash in iOS 10 / macOS 10.12 for transaction metrics caused by timestamps in Apple's
 code (crash is 100% in Apple's stack, no workaround). radar://28301343
 Crash was fixed in iOS 10.2 / macOS 10.12.2, but replaced with a new crash. radar://31812408
 iOS 11 and macOS 13 betas continued with that crash until iOS 11 beta 5 (and matching macOS beta).
 So, for simplicity, this method will return `YES` for iOS 11.0.1+ and macOS 10.13.0+.
 */
+ (BOOL)tnl_URLSessionCanUseTaskTransactionMetrics;

/**
 `NSURLSession` added support for Brotli decoding (`br` in `Content-Encoding`) to iOS 11 and
 macOS 10.13. Requires target SDK be at least the SDK of Brotli introduction.
 @return `YES` if Brotli decoding is enabled.
 */
+ (BOOL)tnl_URLSessionSupportsDecodingBrotliContentEncoding;

/**
 Introduced in iOS 11, `waitsForConnectivity` offers a great deal of control over network requests and
 can help avoid needlessly failing a request that can wait until there is a network connection to execute.
 With iOS 13.0 betas (and matching tvOS, macOS and watchOS versions), regressed `waitsForConnectivity`.
 `NSURLSession` layer no longer calls `NSURLSessionTaskDelegate` `URLSession:taskIsWaitingForConnectivity:`
 rendering the feature impotent and dangerous (easily leading to never finishing network requests which
 can lead to interminable hangs based on the dependencies established on the `TNLRequestOperation`).
 #FB7027774
 For versions of iOS (and other matching OSes) that did not support `waitsForConnectivity` (below iOS 11), this will return `NO`.
 For versions of iOS (and other matching OSes) that have the regression from iOS 13 (just iOS 13.0), this will return `NO`.
 Otherwise, this will return `YES` and `waitsForConnectivity` features can be used.
 */
+ (BOOL)tnl_URLSessionCanUseWaitsForConnectivity;

/**
 Convenience method for appropriately mutating the session configuration's `protocolClasses`
 */
- (void)tnl_insertProtocolClasses:(nullable NSArray<Class> *)additionalClasses;

@end

NS_ASSUME_NONNULL_END

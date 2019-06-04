//
//  NSURLSessionConfiguration+TNLAdditions.h
//  TwitterNetworkLayer
//
//  Created on 8/12/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 __TNL__ additions for `NSURLSessionConfiguration`
 */
@interface NSURLSessionConfiguration (TNLAdditions)

/**
 Returns `NO` if the current OS has a critical bug where
 `URLSession:dataTask:didReceiveResponse:completionHandler:` being implemented in a delegate while
 using an `NSURLProtocol` will render the `NSURLSessionTask` completely unuseable. radar://19494690

 If this method returns `NO`, the use of KVO on the `NSURLSessionTask` instance's `response`
 property is the only viable alternative.
 This has the side effect of needing to be very careful with the KVO or there will be some crashing
 in Apple's networking code, but that is the lesser of the 2 issues.
 */
+ (BOOL)tnl_URLSessionCanReceiveResponseViaDelegate;

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
 Convenience method for appropriately mutating the session configuration's `protocolClasses`
 */
- (void)tnl_insertProtocolClasses:(nullable NSArray<Class> *)additionalClasses;

@end

NS_ASSUME_NONNULL_END

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
 Cement the provided _config_.

 `NSURLSessionConfiguration` objects, by default, lazily generate certain properties.
 These lazy generated values are not persisted in the underlying ivar though and subsequent calls to
 those properties will yield new objects.
 `tnl_cementConfiguration:` provides a mechanism to avoid this implementation detail by sending the
 return value for a property's getter to its setter.  This effectively caches that property for
 reuse and "cements" that property.  Since `NSURLSessionConfiguration` is a class cluster, we
 provide the functionality with a class method instead of an instance method.

 The properties are `URLCache`, `URLCredentialStorage` and `HTTPCookieStorage`

 @discussion __See Also:__ `[NSURLSessionConfiguration URLCache]`,
 `[NSURLSessionConfiguration URLCredentialStorage]` and
 `[NSURLSessionConfiguration HTTPCookieStorage]`

 @note The issue of needing to cement these properties was fixed in __iOS 8__ so this method is a
 no-op on iOS 8+.
 */
+ (void)tnl_cementConfiguration:(NSURLSessionConfiguration *)config;

/**
 Unifies between the two constructors for background session configurations on iOS 7 and iOS 8.

 __See Also:__ `[NSURLSessionConfiguration backgroundSessionConfiguration:]` (iOS 7) and
 `[NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:]` (iOS 8+)
 */
+ (instancetype)tnl_backgroundSessionConfigurationWithIdentifier:(NSString *)identifier;

/**
 Returns `YES` if `NSURLSessionConfiguration` supports the shared container identifier.
 Since `NSURLSessionConfiguration` is a class cluster, you can't use `instancesRespondToSelector:`
 */
+ (BOOL)tnl_supportsSharedContainerIdentifier;

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

@end

NS_ASSUME_NONNULL_END

//
//  TNLContentCoding.h
//  TwitterNetworkLayer
//
//  Created on 11/19/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//! Content Encoding error domain
FOUNDATION_EXTERN NSString * const TNLContentEncodingErrorDomain;
//! Specific Content Encoding error code to stop encoding instead of fail
static const NSInteger TNLContentEncodingErrorCodeSkipEncoding = -1;

/**
 Protocol for supporting custom request _Content-Encoding_
 */
@protocol TNLContentEncoder <NSObject>

/**
 Return the _Content-Encoding_ type.
 For example: `@"gzip"`, `@"deflate"`
 */
- (NSString *)tnl_contentEncodingType;

/**
 Encode an HTTP body's `NSData`
 An error of domain `TNLContentEncodingErrorDomain` and code
 `TNLContentEncodingErrorCodeSkipEncoding` indicates the request should continue without a
 _Content-Encoding_
 */
- (nullable NSData *)tnl_encodeHTTPBody:(NSData *)bodyData
                                  error:(out NSError * __nullable * __nullable)error;

@end

/**
 Client for the `TNLContentDecoder` and `TNLContentDecoderContext`
 This client should be called whenever data is decoded by a decoder and it's context.
 */
@protocol TNLContentDecoderClient <NSObject>
/**
 Method to call when some content is decoded
 */
- (BOOL)tnl_dataWasDecoded:(NSData *)data
                     error:(out NSError * __nullable * __nullable)error;
@end

/**
 Context for a `TNLContentDecoder`
 */
@protocol TNLContentDecoderContext <NSObject>
/**
 Any given context will need a reference to the delegate for when data is decoded.
 This client will outlive the context and should not be retained.
 */
@property (nonatomic, readonly, unsafe_unretained) id<TNLContentDecoderClient> tnl_decoderClient;
@end

/**
 Protocol for supporting custom response _Content-Encoding_.
 All decoder implementations should be able to clean themselves up during `dealloc` without waiting
 for the _finalize_ method.
 @note the `NSURL` layer (which underpins __TNL__) automatically decodes `gzip` and `deflate` (and
 `br` on iOS 11+), so decoders for those codecs are unnecessary.
 */
@protocol TNLContentDecoder <NSObject>

/**
 Return the _Content-Encoding_ type.
 For example: `@"br"`, `@"zstd"`
 */
- (NSString *)tnl_contentEncodingType;

/**
 Initialize the decoding and return a context for followup steps
 */
- (nullable id<TNLContentDecoderContext>)tnl_initializeDecodingWithContentEncoding:(NSString *)contentEncodingValue
                                                                            client:(id<TNLContentDecoderClient>)client
                                                                             error:(out NSError * __nullable * __nullable)error;

/**
 Decode some additional _data_ using the given _context_
 */
- (BOOL)tnl_decode:(id<TNLContentDecoderContext>)context
    additionalData:(NSData *)data
             error:(out NSError * __nullable * __nullable)error;

/**
 Finalize the decoding for the given _context_
 */
- (BOOL)tnl_finalizeDecoding:(id<TNLContentDecoderContext>)context
                       error:(out NSError * __nullable * __nullable)error;

@end

NS_ASSUME_NONNULL_END

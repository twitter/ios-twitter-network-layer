//
//  TNLXContentEncoding.m
//  TwitterNetworkLayer
//
//  Created on 11/21/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#include <zlib.h>

#import <TwitterNetworkLayer/TNLContentCoding.h>

#import "TNLXContentEncoding.h"

typedef NS_ENUM(UInt32, TNLXZLibContentEncoderMode)
{
    TNLXZLibContentEncoderDEFLATE   = 'defl',
    TNLXZLibContentEncoderGZIP      = 'gzip',
};

static const NSUInteger kMinBodySizeForCompression = 512;
#define kGZIP_WINDOW_BITS_OFFSET (16)
#define kWINDOW_BITS (15)
#define kMEM_LIMIT (8)
#define kGZIP_WINDOW_BITS       (kGZIP_WINDOW_BITS_OFFSET+kWINDOW_BITS)
#define kDEFLATE_WINDOW_BITS    (-MAX_WBITS)
static const size_t kZipBufferSize = ((4 * 1024) /*page size*/ * 4);
typedef void(^TIPXDataEnumerateBlock)(const void *bytes, NSRange byteRange, BOOL *stop);

@interface TNLXZLibContentEncoder : NSObject <TNLContentEncoder>
@property (nonatomic, readonly) TNLXZLibContentEncoderMode mode;
- (instancetype)initWithMode:(TNLXZLibContentEncoderMode)mode;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface TNLXZLibContentDecoderContext : NSObject <TNLContentDecoderContext>
@property (nonatomic, readonly) TNLXZLibContentEncoderMode mode;
@property (nonatomic, readonly, nonnull, unsafe_unretained) id<TNLContentDecoderClient> tnl_decoderClient;
- (instancetype)initWithMode:(TNLXZLibContentEncoderMode)mode client:(id<TNLContentDecoderClient>)client;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (BOOL)decodeData:(NSData *)data error:(out NSError **)error;
- (BOOL)finalizeAndReturnError:(out NSError **)error;
@end

@interface TNLXZLibContentDecoder : NSObject <TNLContentDecoder>
@property (nonatomic, readonly) TNLXZLibContentEncoderMode mode;
- (instancetype)initWithMode:(TNLXZLibContentEncoderMode)mode;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface TNLXBase64ContentDecoderContext : NSObject <TNLContentDecoderContext>
@property (nonatomic, readonly, nonnull, unsafe_unretained) id<TNLContentDecoderClient> tnl_decoderClient;
- (instancetype)initWithClient:(id<TNLContentDecoderClient>)client;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (BOOL)decodeData:(NSData *)data error:(out NSError **)error;
- (BOOL)finalizeAndReturnError:(out NSError **)error;
@end

@interface TNLXBase64ContentEncoder : NSObject <TNLContentEncoder>
@end

@interface TNLXBase64ContentDecoder : NSObject <TNLContentDecoder>
@end

@implementation TNLXContentEncoding

+ (id<TNLContentEncoder>)GZIPContentEncoder
{
    return [[TNLXZLibContentEncoder alloc] initWithMode:TNLXZLibContentEncoderGZIP];
}

+ (id<TNLContentDecoder>)GZIPContentDecoder
{
    return [[TNLXZLibContentDecoder alloc] initWithMode:TNLXZLibContentEncoderGZIP];
}

+ (id<TNLContentEncoder>)DEFLATEContentEncoder
{
    return [[TNLXZLibContentEncoder alloc] initWithMode:TNLXZLibContentEncoderDEFLATE];
}

+ (id<TNLContentDecoder>)DEFLATEContentDecoder
{
    return [[TNLXZLibContentDecoder alloc] initWithMode:TNLXZLibContentEncoderDEFLATE];
}

+ (id<TNLContentEncoder>)Base64ContentEncoder
{
    return [[TNLXBase64ContentEncoder alloc] init];
}

+ (id<TNLContentDecoder>)Base64ContentDecoder
{
    return [[TNLXBase64ContentDecoder alloc] init];
}

@end

@implementation TNLXZLibContentEncoder

- (instancetype)initWithMode:(TNLXZLibContentEncoderMode)mode
{
    if (self = [super init]) {
        _mode = mode;
    }
    return self;
}

- (NSString *)tnl_contentEncodingType
{
    return (TNLXZLibContentEncoderGZIP == _mode) ? @"gzip" : @"deflate";
}

- (NSData *)tnl_encodeHTTPBody:(NSData *)bodyData
                         error:(out NSError **)error
{
    if (bodyData.length < kMinBodySizeForCompression) {
        if (error) {
            *error = [NSError errorWithDomain:TNLContentEncodingErrorDomain
                                         code:TNLContentEncodingErrorCodeSkipEncoding
                                     userInfo:nil];
        }
        return nil;
    }

    NSMutableData *mData = [NSMutableData data];
    __block int zRetVal;
    z_stream zStream;
    __block z_streamp zStreamPtr = &zStream;
    memset(zStreamPtr, 0, sizeof(z_stream));

    zRetVal = deflateInit2(zStreamPtr,
                           Z_DEFAULT_COMPRESSION,
                           Z_DEFLATED,
                           (TNLXZLibContentEncoderGZIP == _mode) ? kGZIP_WINDOW_BITS : kDEFLATE_WINDOW_BITS,
                           kMEM_LIMIT,
                           Z_DEFAULT_STRATEGY);
    if (zRetVal == Z_OK) {

        unsigned char *outBuffer = (unsigned char *)malloc(kZipBufferSize);

        TIPXDataEnumerateBlock enumBlock = ^(const void *bytes, NSRange byteRange, BOOL *stop) {

            zStreamPtr->avail_in = (uInt)byteRange.length;
            zStreamPtr->next_in = (z_const Byte *)bytes;

            const int flush = byteRange.length > 0 ? Z_NO_FLUSH : Z_FINISH;

            do {

                zStreamPtr->avail_out = kZipBufferSize;
                zStreamPtr->next_out = outBuffer;

                zRetVal = deflate(zStreamPtr, flush);

                if (Z_OK != zRetVal && Z_STREAM_END != zRetVal) {
                    // failure
                    break;
                }

                const uInt bytesMoved = kZipBufferSize - zStreamPtr->avail_out;
                if (bytesMoved) {
                    [mData appendBytes:outBuffer length:bytesMoved];
                }

                if (Z_STREAM_END == zRetVal) {
                    // done
                    break;
                }

                if (Z_FINISH != flush && zStreamPtr->avail_in == 0) {
                    // no more data to consume
                    break;
                }

            } while (true);

            if (Z_OK != zRetVal) {
                *stop = YES;
            }
        };

        [bodyData enumerateByteRangesUsingBlock:enumBlock];
        if (zRetVal == Z_OK) {
            BOOL fakeStop;
            enumBlock(NULL, NSMakeRange(bodyData.length, 0), &fakeStop);
            if (zRetVal == Z_STREAM_END) {
                zRetVal = Z_OK;
            } else if (zRetVal == Z_OK) {
                zRetVal = Z_STREAM_ERROR;
            }
        }

        free(outBuffer);
        (void)deflateEnd(zStreamPtr);
    }

    if (Z_OK != zRetVal) {
        mData = nil;
        if (error) {
            *error = [NSError errorWithDomain:@"zlib.error" code:zRetVal userInfo:nil];
        }
    }
    return mData;
}

@end

@implementation TNLXZLibContentDecoder

- (instancetype)initWithMode:(TNLXZLibContentEncoderMode)mode
{
    if (self = [super init]) {
        _mode = mode;
    }
    return self;
}

- (NSString *)tnl_contentEncodingType
{
    return (TNLXZLibContentEncoderGZIP == _mode) ? @"gzip" : @"deflate";
}

- (id<TNLContentDecoderContext>)tnl_initializeDecodingWithContentEncoding:(NSString *)contentEncodingValue
                                                                   client:(id<TNLContentDecoderClient>)client
                                                                    error:(out NSError **)error
{
    return [[TNLXZLibContentDecoderContext alloc] initWithMode:_mode client:client];
}

- (BOOL)tnl_decode:(TNLXZLibContentDecoderContext *)context
    additionalData:(NSData *)data
             error:(out NSError **)error
{
    return [context decodeData:data error:error];
}

- (BOOL)tnl_finalizeDecoding:(TNLXZLibContentDecoderContext *)context error:(out NSError **)error
{
    return [context finalizeAndReturnError:error];
}

@end

@implementation TNLXZLibContentDecoderContext
{
    z_stream _zStream;

    unsigned char _outBuffer[kZipBufferSize];
    unsigned char *_outRef;

    struct {
        int zStatus;
        BOOL didInit:1;
    } _flags;
}

- (instancetype)initWithMode:(TNLXZLibContentEncoderMode)mode
                      client:(id<TNLContentDecoderClient>)client
{
    if (self = [super init]) {
        _mode = mode;
        _tnl_decoderClient = client;

        _flags.zStatus = inflateInit2(&_zStream,
                                      (TNLXZLibContentEncoderGZIP == _mode) ? kGZIP_WINDOW_BITS : kDEFLATE_WINDOW_BITS);
        if (Z_OK == _flags.zStatus) {
            _outRef = _outBuffer;
            _flags.didInit = 1;
        }
    }
    return self;
}

- (void)dealloc
{
    if (_flags.didInit) {
        inflateEnd(&_zStream);
    }
}

- (BOOL)decodeData:(NSData *)data error:(out NSError * __autoreleasing *)error
{
    if (Z_OK == _flags.zStatus || Z_STREAM_END == _flags.zStatus) {
        [data enumerateByteRangesUsingBlock:^(const void *bytes, NSRange byteRange, BOOL *stop) {
            *stop = ![self decodeBytes:bytes
                                length:byteRange.length
                                 error:error];
            if (self->_flags.zStatus != Z_OK && self->_flags.zStatus != Z_STREAM_END) {
                *stop = YES;
            }
        }];
    }

    if (error && *error) {
        return NO;
    }

    if (Z_OK != _flags.zStatus && Z_STREAM_END != _flags.zStatus) {
        if (error) {
            *error = [NSError errorWithDomain:@"zlib.error"
                                         code:_flags.zStatus
                                     userInfo:nil];
        }
        return NO;
    }

    return YES;
}

- (BOOL)decodeBytes:(const Byte *)bytes
             length:(NSUInteger)length
              error:(out NSError **)error
{
    _zStream.avail_in = (uInt)length;
    _zStream.next_in = (z_const Byte *)bytes;
    BOOL inflateSuccess = NO;

    do {

        _zStream.avail_out = kZipBufferSize;
        _zStream.next_out = _outRef;

        _flags.zStatus = inflate(&_zStream, Z_NO_FLUSH);
        inflateSuccess = (Z_OK == _flags.zStatus || Z_STREAM_END == _flags.zStatus);

        uInt bytesMoved = kZipBufferSize - _zStream.avail_out;
        if (inflateSuccess && bytesMoved) {
            id<TNLContentDecoderClient> delegate = self.tnl_decoderClient;
            NSData *data = [NSData dataWithBytes:_outRef length:bytesMoved];
            if (![delegate tnl_dataWasDecoded:data error:error]) {
                return NO;
            }
        }

    } while (_zStream.avail_out == 0 && inflateSuccess);
    assert(_zStream.avail_in == 0);

    return YES;
}

- (BOOL)finalizeAndReturnError:(out NSError **)error
{
    if (_flags.zStatus == Z_OK) {
        if (![self decodeBytes:NULL length:0 error:error]) {
            return NO;
        }
    }

    if (_flags.zStatus == Z_STREAM_END) {
        return YES;
    }

    if (error) {
        *error = [NSError errorWithDomain:@"zlib.error"
                                     code:((_flags.zStatus == Z_OK) ? Z_STREAM_ERROR : _flags.zStatus)
                                 userInfo:nil];
    }
    return NO;
}

@end

@implementation TNLXBase64ContentEncoder

- (NSString *)tnl_contentEncodingType
{
    return @"base64";
}

- (NSData *)tnl_encodeHTTPBody:(NSData *)bodyData error:(out NSError **)error
{
    return [bodyData base64EncodedDataWithOptions:(NSDataBase64Encoding64CharacterLineLength |
                                                   NSDataBase64EncodingEndLineWithCarriageReturn |
                                                   NSDataBase64EncodingEndLineWithLineFeed)];
}

@end

@implementation TNLXBase64ContentDecoder

- (NSString *)tnl_contentEncodingType
{
    return @"base64";
}

- (id<TNLContentDecoderContext>)tnl_initializeDecodingWithContentEncoding:(NSString *)contentEncodingValue
                                                                   client:(id<TNLContentDecoderClient>)client
                                                                    error:(out NSError **)error
{
    return [[TNLXBase64ContentDecoderContext alloc] initWithClient:client];
}

- (BOOL)tnl_decode:(TNLXBase64ContentDecoderContext *)context
    additionalData:(NSData *)data
             error:(out NSError **)error
{
    return [context decodeData:data error:error];
}

- (BOOL)tnl_finalizeDecoding:(TNLXBase64ContentDecoderContext *)context
                       error:(out NSError **)error
{
    return [context finalizeAndReturnError:error];
}

@end

@implementation TNLXBase64ContentDecoderContext
{
    NSMutableData *_carryOverData;
}

- (instancetype)initWithClient:(id<TNLContentDecoderClient>)client
{
    if (self = [super init]) {
        _tnl_decoderClient = client;
    }
    return self;
}

- (BOOL)decodeData:(NSData *)data error:(out NSError **)error
{
    NSData *decodedData = nil;
    if (_carryOverData) {
        [_carryOverData appendData:data];
        decodedData = [[NSData alloc] initWithBase64EncodedData:_carryOverData
                                                        options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (decodedData) {
            _carryOverData = nil;
        }
    } else {
        decodedData = [[NSData alloc] initWithBase64EncodedData:data
                                                        options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (!decodedData) {
            _carryOverData = [data mutableCopy];
        }
    }

    if (decodedData) {
        return [_tnl_decoderClient tnl_dataWasDecoded:decodedData error:error];
    }

    return YES;
}

- (BOOL)finalizeAndReturnError:(out NSError **)error
{
    if (_carryOverData) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:nil];
        }
        return NO;
    }

    return YES;
}

@end

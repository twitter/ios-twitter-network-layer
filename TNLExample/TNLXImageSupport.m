//
//  TNLXImageSupport.m
//  TwitterNetworkLayer
//
//  Created on 8/18/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLXImageSupport.h"

#if TARGET_OS_IOS
@import UIKit;

#define MAX_CONNECTIONS (-1) // 4

@implementation TNLRequestOperationQueue (Images)

+ (instancetype)tnlx_imageRequestOperationQueue
{
    static TNLRequestOperationQueue *sOperationQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sOperationQueue = [[TNLRequestOperationQueue alloc] initWithIdentifier:@"com.twitter.image.operation.queue"];
    });
    return sOperationQueue;
}

@end

@implementation TNLRequestConfiguration (Images)

+ (instancetype)tnlx_imageRequestConfiguration
{
    static TNLRequestConfiguration *sConfig = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Prepare a request configuration.
        TNLMutableRequestConfiguration *requestConfig = [[TNLMutableRequestConfiguration alloc] init];
        requestConfig.responseDataConsumptionMode = TNLResponseDataConsumptionModeStoreInMemory;
        requestConfig.idleTimeout = 30;
        requestConfig.attemptTimeout = 90;
        requestConfig.operationTimeout = 180;
        requestConfig.cachePolicy = NSURLRequestReturnCacheDataElseLoad;
        requestConfig.URLCache = [NSURLCache tnl_sharedURLCacheProxy];
        //requestConfig.URLCache = [NSURLCache tnl_impotentURLCache];
        //requestConfig.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:64 * 1024 diskCapacity:64 * 1024 diskPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"TNLX_Images"]];

#if 1
        [requestConfig.URLCache removeAllCachedResponses];
#endif

        sConfig = [requestConfig copy];
    });
    return sConfig;
}

@end

@implementation TNLXImageRequest

+ (dispatch_queue_t)backgroundQueue
{
    static dispatch_queue_t sQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sQueue = dispatch_queue_create("image.request.delegate.queue", DISPATCH_QUEUE_SERIAL); // purely for illustration
    });
    return sQueue;
}

+ (instancetype)imageRequestWithURL:(NSURL *)url
{
    return [self imageRequestWithURL:url
                   desiredDimensions:CGSizeZero
                         contentMode:UIViewContentModeTopLeft];
}

+ (instancetype)imageRequestWithURL:(NSURL *)url
                  desiredDimensions:(CGSize)dimensions
                        contentMode:(UIViewContentMode)contentMode
{
    return [[[self class] alloc] initWithURL:url
                           desiredDimensions:dimensions
                                 contentMode:contentMode];
}

- (instancetype)init
{
    return [self initWithURL:nil
           desiredDimensions:CGSizeZero
                 contentMode:UIViewContentModeTopLeft];
}

- (instancetype)initWithURL:(NSURL *)url
          desiredDimensions:(CGSize)dimensions
                contentMode:(UIViewContentMode)contentMode
{
    if (self = [super init]) {
        _URL = url;
        _dimensions = dimensions;
        _contentMode = contentMode;
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    return [self isEqualToRequest:object];
}

- (BOOL)isEqualToRequest:(id<TNLRequest>)request
{
    if (!TNLRequestEqualToRequest(self, request, NO /*quickBodyCheck*/)) {
        return NO;
    }

    UIViewContentMode otherContentMode = UIViewContentModeTopLeft;
    CGSize otherDims = CGSizeZero;
    if ([request isKindOfClass:[TNLXImageRequest class]]) {
        otherContentMode = [(TNLXImageRequest *)request contentMode];
        otherDims = [(TNLXImageRequest *)request dimensions];
    }

    return self.contentMode == otherContentMode && CGSizeEqualToSize(self.dimensions, otherDims);
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

@implementation TNLXImageResponse

- (void)prepare
{
    [super prepare];
    [self populateImage];
}

- (void)populateImage
{
    id<TNLRequest> request = self.originalRequest;

    UIViewContentMode mode = UIViewContentModeTopLeft;
    CGSize desiredDims = CGSizeZero;
    if ([request isKindOfClass:[TNLXImageRequest class]]) {
        mode = [(TNLXImageRequest *)request contentMode];
        desiredDims = [(TNLXImageRequest *)request dimensions];
    }

    _requestContentMode = mode;
    _requestImageDimensions = desiredDims;

    if (!self.operationError) {
        NSError *error = nil;
        if (!self.info.data) {
            error = [NSError errorWithDomain:NSStringFromClass([self class]) code:-1 userInfo:nil];
        } else {
            UIImage *image = [UIImage imageWithData:self.info.data];
            if (!image) {
                error = [NSError errorWithDomain:NSStringFromClass([self class]) code:-2 userInfo:nil];
            } else {

                CGSize currentDims = image.size;
                currentDims.width *= image.scale;
                currentDims.height *= image.scale;
                _rawImageDimensions = currentDims;

                CGSize scaledDims = TNLXSizeScale(currentDims, desiredDims, mode);
                _scaledImageDimensions = scaledDims;

                UIGraphicsBeginImageContextWithOptions(scaledDims, NO, 1.0);
                CGRect scaledImageRect = (CGRect){ CGPointZero, scaledDims };
                [image drawInRect:scaledImageRect];
                image = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();

                _image = image;
            }
        }

        if (error) {
            NSLog(@"%@", error);
            _operationError = error;
        }
    }
}

@end

@interface TNLXImageView () <TNLRequestDelegate>
@end

@implementation TNLXImageView
{
    TNLRequestOperation *_imageOp;
    UIProgressView *_progressView;
    UILabel *_loadingURLLabel;
    TNLMutableRequestConfiguration *_config;
    NSURL *_selectedImageURL;
}

@synthesize imageLoadOperation = _imageOp;

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        frame.size.width -= 40;
        frame.origin.x = 20;
        frame.origin.y = (CGFloat)round(((frame.size.height - _progressView.frame.size.height) / 2.0));
        frame.size.height = _progressView.frame.size.height;
        _progressView.frame = frame;
        _progressView.transform = CGAffineTransformMakeScale(1.0f, 22.0f / frame.size.height);
        _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
        _progressView.backgroundColor = [UIColor darkTextColor];
        [self addSubview:_progressView];
        _progressView.hidden = YES;

        //        frame.origin.y += 3.0;
        frame.size.height = 22;
        _loadingURLLabel = [[UILabel alloc] initWithFrame:frame];
        _loadingURLLabel.font = [UIFont systemFontOfSize:16];
        _loadingURLLabel.textColor = [UIColor whiteColor];
        _loadingURLLabel.textAlignment = NSTextAlignmentCenter;
        _loadingURLLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _loadingURLLabel.numberOfLines = 1;
        _loadingURLLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
        [self addSubview:_loadingURLLabel];
        _loadingURLLabel.hidden = YES;
        _progressView.center = _loadingURLLabel.center;

        _config = [[TNLRequestConfiguration tnlx_imageRequestConfiguration] mutableCopy];
    }
    return self;
}

#pragma mark - TNLRequestDelegate

- (dispatch_queue_t)tnl_delegateQueueForRequestOperation:(TNLRequestOperation *)op
{
    return [TNLXImageRequest backgroundQueue];
}

#pragma mark - TNLRequestEventHandler

- (void)tnl_requestOperation:(TNLRequestOperation *)op didUpdateDownloadProgress:(float)downloadProgress
{
    if ([NSThread isMainThread]) {
        if (op == _imageOp) {
            [_progressView setProgress:downloadProgress animated:YES];
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self tnl_requestOperation:op didUpdateDownloadProgress:downloadProgress];
        });
    }
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteWithResponse:(TNLXImageResponse *)response
{
    NSURL *responseURL = op.hydratedRequest.URL;
    UIImage *image = response.image;
    float progress = op.downloadProgress;

    assert([NSThread isMainThread]);

    _imageOp = nil;
    if ([_selectedImageURL isEqual:responseURL]) {
        self.image = image;
        if (!image) {
            NSString *errorText = nil;
            if (errorText.length == 0 && response.operationError) {
                errorText = response.operationError.description;
            }
            if (errorText.length == 0 && !TNLHTTPStatusCodeIsSuccess(response.info.statusCode)) {
                errorText = [NSString stringWithFormat:@"HTTP Status == %li", (long)response.info.statusCode];
            }
            if (errorText.length == 0) {
                errorText = @"ERROR";
            }
            _loadingURLLabel.text = errorText;
            _loadingURLLabel.hidden = NO;
            _progressView.progress = progress;
            _progressView.hidden = NO;
        }
    }
}

#pragma mark View Methods

- (void)setImage:(UIImage *)image
{
    [self _cancelLoad];
    [super setImage:image];
}

- (void)setImageEntity:(id<TAPIImageEntityModel>)imageEntity
{
    CGSize dims = self.bounds.size;
    dims.width *= [UIScreen mainScreen].scale;
    dims.height *= [UIScreen mainScreen].scale;
    NSURL *bestURL = TNLXSelectBestImageURL(imageEntity, dims, self.contentMode);
    const BOOL different = ![_selectedImageURL isEqual:bestURL];
    _imageEntity = imageEntity;
    _selectedImageURL = bestURL;
    if (different) {
        self.image = nil;
        _loadingURLLabel.text = bestURL.absoluteString;
        [self _load];
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.imageEntity = _imageEntity;
}

- (void)didMoveToWindow
{
    if (self.window) {
        [self _load];
    }
}

- (void)_cancelLoad
{
    [_imageOp cancelWithSource:NSStringFromSelector(_cmd)];
    _imageOp = nil;
    _progressView.hidden = YES;
    _progressView.progress = 0;
    _loadingURLLabel.hidden = YES;
}

- (void)_load
{
    if (_selectedImageURL && !_imageOp && !self.image && self.window) {
        _progressView.hidden = NO;
        _progressView.progress = 0;
        _loadingURLLabel.hidden = NO;
        CGSize dims = self.bounds.size;
        dims.width *= [UIScreen mainScreen].scale;
        dims.height *= [UIScreen mainScreen].scale;
        TNLXImageRequest *request = [[TNLXImageRequest alloc] initWithURL:_selectedImageURL
                                                        desiredDimensions:dims
                                                              contentMode:self.contentMode];
        _imageOp = [TNLRequestOperation operationWithRequest:request
                                               responseClass:[TNLXImageResponse class]
                                               configuration:_config
                                                    delegate:self];
        _imageOp.priority = TNLPriorityNormal;
        [[TNLRequestOperationQueue tnlx_imageRequestOperationQueue] enqueueRequestOperation:_imageOp];
    }
}

- (void)willMoveToWindow:(UIWindow *)newWindow
{
    [super willMoveToWindow:newWindow];
    _imageOp.priority = (newWindow != nil) ? TNLPriorityNormal : TNLPriorityLow;
}

- (void)dealloc
{
    [self _cancelLoad];
}

@end

static id<TAPIImageEntityVariantModel> _SelectBestImageVariant(id<TAPIImageEntityModel> model, CGSize targetDimensions, UIViewContentMode targetContentMode)
{
    if (targetDimensions.width <= 0 || targetDimensions.height <= 0) {
        return model.variants.lastObject;
    }

    id<TAPIImageEntityVariantModel> selectedVariant = nil;
    for (NSUInteger idx = 0; idx < model.variants.count && !selectedVariant; idx++) {
        id<TAPIImageEntityVariantModel> variant = model.variants[idx];
        switch (targetContentMode) {
            case UIViewContentModeScaleAspectFit:
            {
                if (variant.dimensions.width >= targetDimensions.width || variant.dimensions.height >= targetDimensions.height) {
                    selectedVariant = variant;
                }
                break;
            }
            case UIViewContentModeScaleAspectFill:
            {
                if (variant.dimensions.width >= targetDimensions.width && variant.dimensions.height >= targetDimensions.height) {
                    selectedVariant = variant;
                }
                break;
            }
            default:
            {
                if (variant.dimensions.width >= targetDimensions.width || variant.dimensions.height >= targetDimensions.height) {
                    if (idx > 0) {
                        idx--;
                    }
                    selectedVariant = model.variants[idx];
                }
                break;
            }
        }
    }

    return selectedVariant ?: model.variants.lastObject;
}

NSURL *TNLXSelectBestImageURL(id<TAPIImageEntityModel> model, CGSize targetDimensions, UIViewContentMode targetContentMode)
{
    id<TAPIImageEntityVariantModel> variant = _SelectBestImageVariant(model, targetDimensions, targetContentMode);
    NSString *URLString = [NSString stringWithFormat:@"%@?format=%@&name=%@", model.baseURLString, model.format, variant.name];
    return [NSURL URLWithString:URLString];
}

CGSize TNLXSizeScale(CGSize sourceSize, CGSize desiredSize, UIViewContentMode contentMode)
{
    switch (contentMode) {
        case UIViewContentModeScaleToFill:
            return desiredSize;
        case UIViewContentModeScaleAspectFit:
        case UIViewContentModeScaleAspectFill:
        {
            CGFloat widthRatio = sourceSize.width / desiredSize.width;
            CGFloat heightRatio = sourceSize.height / desiredSize.height;

            if (UIViewContentModeScaleAspectFit == contentMode) {
                if (heightRatio > widthRatio) {
                    widthRatio = heightRatio;
                }
            } else {
                if (heightRatio < widthRatio) {
                    widthRatio = heightRatio;
                }
            }

            desiredSize.width = (CGFloat)floor(sourceSize.width * 2.0f / widthRatio) / 2.0f;
            desiredSize.height = (CGFloat)floor(sourceSize.height * 2.0f / widthRatio) / 2.0f;
            return desiredSize;
        }
        case UIViewContentModeRedraw:
        case UIViewContentModeCenter:
        case UIViewContentModeTop:
        case UIViewContentModeBottom:
        case UIViewContentModeLeft:
        case UIViewContentModeRight:
        case UIViewContentModeTopLeft:
        case UIViewContentModeTopRight:
        case UIViewContentModeBottomLeft:
        case UIViewContentModeBottomRight:
            return sourceSize;
    }
}

#endif

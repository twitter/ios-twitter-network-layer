//
//  TNLXImageSupport.h
//  TwitterNetworkLayer
//
//  Created on 8/18/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>
#import "TAPIModel.h"

#if TARGET_OS_IOS
@import UIKit;

@interface TNLRequestOperationQueue (Images)
+ (instancetype)tnlx_imageRequestOperationQueue;
@end

@interface TNLRequestConfiguration (Images)
+ (instancetype)tnlx_imageRequestConfiguration;
@end

@interface TNLXImageRequest : NSObject <TNLRequest>

@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) CGSize dimensions;
@property (nonatomic, readonly) UIViewContentMode contentMode;

+ (dispatch_queue_t)backgroundQueue;

+ (instancetype)imageRequestWithURL:(NSURL *)url;
+ (instancetype)imageRequestWithURL:(NSURL *)url
                  desiredDimensions:(CGSize)dimensions
                        contentMode:(UIViewContentMode)contentMode;
- (instancetype)initWithURL:(NSURL *)url
          desiredDimensions:(CGSize)dimensions
                contentMode:(UIViewContentMode)contentMode NS_DESIGNATED_INITIALIZER;

@end

@interface TNLXImageResponse : TNLResponse

@property (nonatomic, readonly) UIImage *image;

@property (nonatomic, readonly) CGSize requestImageDimensions;
@property (nonatomic, readonly) UIViewContentMode requestContentMode;

@property (nonatomic, readonly) CGSize scaledImageDimensions; // == image.size * image.scale
@property (nonatomic, readonly) CGSize rawImageDimensions;

@end

FOUNDATION_EXTERN CGSize TNLXSizeScale(CGSize sourceSize, CGSize desiredSize, UIViewContentMode contentMode) __attribute__((const));
FOUNDATION_EXTERN NSURL *TNLXSelectBestImageURL(id<TAPIImageEntityModel> model, CGSize targetDimensions, UIViewContentMode targetContentMode);

@interface TNLXImageView : UIImageView
@property (nonatomic) BOOL loaded;
@property (nonatomic) id<TAPIImageEntityModel> imageEntity;
@property (nonatomic, readonly) NSOperation *imageLoadOperation;
@end

#endif

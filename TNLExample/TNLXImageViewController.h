//
//  TNLXImageViewController.h
//  TwitterNetworkLayer
//
//  Created on 8/18/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

@import UIKit;

@protocol TAPIImageEntityModel;

@interface TNLXImageViewController : UIViewController

@property (nonatomic, readonly) NSURL *imageURL;
@property (nonatomic, readonly) CGSize imageDimensions;

@property (nonatomic) UIImage *lowResImage;
@property (nonatomic) UIImage *highResImage;
@property (nonatomic) NSOperation *blockingOperation;

- (instancetype)initWithURL:(NSURL *)url imageDimensions:(CGSize)dims;
- (instancetype)initWithImageEntity:(id<TAPIImageEntityModel>)imageEntity;

@end

//
//  TNLXImageViewController.m
//  TwitterNetworkLayer
//
//  Created on 8/18/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

#import "TAPI.h"

#import "TNLXImageSupport.h"
#import "TNLXImageViewController.h"

@import UIKit;

@interface TNLXImageViewController () <UIScrollViewDelegate, TNLRequestDelegate>
{
    UIScrollView *_scrollView;
    UIImageView *_contentImageView;
}

@property (nonatomic) TNLRequestOperation *activeOp;

@end

@implementation TNLXImageViewController

- (instancetype)initWithImageEntity:(id<TAPIImageEntityModel>)imageEntity
{
    id<TAPIImageEntityVariantModel> maxVariant = imageEntity.variants.lastObject;
    NSString *imageURLString = [NSString stringWithFormat:@"%@?format=%@&name=%@", imageEntity.baseURLString, imageEntity.format, maxVariant.name];
    return [self initWithURL:[NSURL URLWithString:imageURLString]
             imageDimensions:maxVariant.dimensions];
}

- (instancetype)initWithURL:(NSURL *)url imageDimensions:(CGSize)dims
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        _imageURL = url;
        _imageDimensions = dims;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    CGSize size = _imageDimensions;
    size.height /= [UIScreen mainScreen].scale;
    size.width /= [UIScreen mainScreen].scale;
    _contentImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _contentImageView.contentMode = UIViewContentModeScaleAspectFit;
    _contentImageView.backgroundColor = [UIColor whiteColor];
    _contentImageView.opaque = YES;
    _contentImageView.frame = (CGRect){ CGPointZero, size };

    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _scrollView.contentSize = size;
    [_scrollView addSubview:_contentImageView];
    _scrollView.opaque = YES;

    _scrollView.delegate = self;
    _scrollView.maximumZoomScale = 2.0;
    _scrollView.minimumZoomScale = MIN((CGFloat)1.0, (MIN(_scrollView.bounds.size.width, _scrollView.bounds.size.height) / MAX(size.width, size.height)));
    _scrollView.zoomScale = _scrollView.minimumZoomScale;

    UITapGestureRecognizer *tapper = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    tapper.numberOfTapsRequired = 2;
    [_scrollView addGestureRecognizer:tapper];

    [self.view addSubview:_scrollView];
}

- (void)doubleTap:(UITapGestureRecognizer *)tapper
{
    BOOL isMin = fabs(_scrollView.minimumZoomScale - _scrollView.zoomScale) < 0.05;
    [_scrollView setZoomScale:(isMin) ? _scrollView.maximumZoomScale : _scrollView.minimumZoomScale animated:YES];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return _contentImageView;
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView
                       withView:(UIView *)view
                        atScale:(CGFloat)scale
{

}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (!_activeOp && !_highResImage) {
        TNLXImageRequest *imageRequest = [TNLXImageRequest imageRequestWithURL:_imageURL];
        _activeOp = [TNLRequestOperation operationWithRequest:imageRequest
                                                responseClass:[TNLXImageResponse class]
                                                configuration:nil
                                                     delegate:self];
        if (_blockingOperation) {
            [_activeOp addDependency:_blockingOperation];
        }
        [[TNLRequestOperationQueue tnlx_imageRequestOperationQueue] enqueueRequestOperation:_activeOp];
    }

    [self updateUI];
}

- (void)updateUI
{
    if (_highResImage) {
        _contentImageView.image = _highResImage;
    } else if (_lowResImage) {
        _contentImageView.image = _lowResImage;
    } else {
        _contentImageView.image = nil;
    }

    if (_contentImageView.image) {
        _contentImageView.alpha = (_activeOp) ? 0.5f : 1.0f;
        _contentImageView.backgroundColor = [UIColor whiteColor];
        _scrollView.backgroundColor = [UIColor whiteColor];
    } else {
        _contentImageView.backgroundColor = [UIColor grayColor];
        _scrollView.backgroundColor = [UIColor grayColor];
    }
}

- (void)setLowResImage:(UIImage *)lowResImage
{
    _lowResImage = lowResImage;
    [self updateUI];
}

- (void)setHighResImage:(UIImage *)highResImage
{
    _highResImage = highResImage;
    [self updateUI];
}

- (void)dealloc
{
    [_activeOp cancelWithSource:@"navigated away"];
}

#pragma mark - TNL

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TNLXImageResponse *)response
{
    assert([NSThread isMainThread]);
    _highResImage = response.image;
    _activeOp = nil;
    _blockingOperation = nil;

    [self updateUI];
}

@end

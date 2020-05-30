//
//  TNLXFirstViewController.m
//  TNLExample
//
//  Created on 7/24/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <objc/runtime.h>
#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

#import "TAPI.h"

#import "TNLXImageSupport.h"
#import "TNLXImageTableViewController.h"
#import "TNLXImageViewController.h"

@import UIKit;

#define REDUNDANCY_COUNT (0)
#define COUNT (50)

@interface TNLXImageTableViewController () <UITableViewDataSource, UITableViewDelegate, TNLRequestDelegate>
{
    IBOutlet UIProgressView *_initialLoadProgressView;
    IBOutlet UITableView *_tableView;

    TNLRequestOperation *_initialOp;
    NSArray<id<TAPIImageEntityModel>> *_results;
}

@end

@interface TNLXImageCell : UITableViewCell
@property (nonatomic, readonly) TNLXImageView *smartImageView;
@end

@implementation TNLXImageTableViewController

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [_tableView registerClass:[TNLXImageCell class] forCellReuseIdentifier:@"ImageCell"];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self _startInitialLoadIfNeeded];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self _cleanupInitialLoadIfNotFinished];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    TNLXImageCell *cell = (id)[tableView cellForRowAtIndexPath:indexPath];
    id<TAPIImageEntityModel> info = cell.smartImageView.imageEntity;
    TNLXImageViewController *vc = [[TNLXImageViewController alloc] initWithImageEntity:info];
    vc.lowResImage = cell.smartImageView.image;
    vc.blockingOperation = cell.smartImageView.imageLoadOperation;
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close"
                                                                           style:UIBarButtonItemStyleDone
                                                                          target:self
                                                                          action:@selector(dismissImageViewController)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [cell.smartImageView addObserver:self
                          forKeyPath:@"image"
                             options:NSKeyValueObservingOptionNew
                             context:NULL];
    [self presentViewController:nav animated:YES completion:NULL];
}

- (void)dismissImageViewController
{
    TNLXImageCell *cell = (id)[_tableView cellForRowAtIndexPath:_tableView.indexPathForSelectedRow];
    [cell.smartImageView removeObserver:self forKeyPath:@"image"];
    [_tableView deselectRowAtIndexPath:_tableView.indexPathForSelectedRow animated:YES];
    [self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    UINavigationController *nav = (id)self.presentedViewController;
    TNLXImageViewController *vc = (id)nav.viewControllers[0];
    [vc setLowResImage:[(TNLXImageView *)object image]];
}

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TNLXImageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ImageCell" forIndexPath:indexPath];
    cell.contentView.frame = cell.bounds;
    assert(cell != nil);
    cell.smartImageView.imageEntity = _results[(NSUInteger)indexPath.row];
    return cell;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)_results.count;
}

#pragma mark - TNL

- (void)tnl_requestOperation:(TNLRequestOperation *)op
     didCompleteWithResponse:(TAPISearchResponse *)response
{
    assert([NSThread isMainThread]);

    if (!_initialOp) {
        return;
    }

    _initialOp = nil;
    NSArray *results = [response imagesFromStatuesRemovingSensitiveImages:YES];
    _results = _results ? [_results arrayByAddingObjectsFromArray:results] : results;

    if (_results.count < COUNT && response.nextResultsObject) {
        [_initialLoadProgressView setProgress:(float)((double)_results.count / (double)COUNT) animated:YES];
        [self _continueLoading:response.nextResultsObject];
        return;
    }

    [_initialLoadProgressView setProgress:1.0 animated:YES];
    _initialLoadProgressView.hidden = YES;
    _tableView.hidden = NO;
    [_tableView reloadData];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
              hydrateRequest:(TAPIRequest *)request
                  completion:(TNLRequestHydrateCompletionBlock)complete
{
    [[TAPIClient sharedInstance] tnl_requestOperation:op
                                       hydrateRequest:request
                                           completion:complete];
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op
         authorizeURLRequest:(NSURLRequest *)URLRequest
                  completion:(TNLAuthorizeCompletionBlock)completion
{
    [[TAPIClient sharedInstance] tnl_requestOperation:op
                                  authorizeURLRequest:URLRequest
                                           completion:completion];
}

#pragma mark - Private

- (void)_startInitialLoadIfNeeded
{
    if (!_initialOp && !_results) {
        _initialLoadProgressView.progress = 0;
        _initialLoadProgressView.hidden = NO;
        _tableView.hidden = YES;

        TAPISearchRequest *request = [[TAPISearchRequest alloc] initWithQuery:@"Star Wars"];
        // TODO request.redundancyCount = REDUNDANCY_COUNT;

        _initialOp = [[TAPIClient sharedInstance] startRequest:request
                                                      delegate:self];
    }
}

- (void)_continueLoading:(id)nextResultsObject
{
    assert(!_initialOp);
    if (!_initialOp) {
        TAPISearchRequest *request = [[TAPISearchRequest alloc] initWithNextResultsObject:nextResultsObject];
        // TODO request.redundancyCount = REDUNDANCY_COUNT;

        _initialOp = [[TAPIClient sharedInstance] startRequest:request
                                                      delegate:self];
    }
}

- (void)_cleanupInitialLoadIfNotFinished
{
    if (_initialOp) {
        [_initialOp cancelWithSource:NSStringFromSelector(_cmd)];
        _initialOp = nil;
        _initialLoadProgressView.progress = 0;
    }
}

@end

@implementation TNLXImageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        _smartImageView = [[TNLXImageView alloc] initWithFrame:self.contentView.bounds];
        _smartImageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        _smartImageView.contentMode = UIViewContentModeScaleAspectFit;

        [self.contentView addSubview:_smartImageView];
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) {
            self.separatorInset = UIEdgeInsetsZero;
        }
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    _smartImageView.image = nil;
}

@end

//
//  TNLSafeOperation.h
//  TwitterNetworkLayer
//
//  Created on 6/1/17
//  Copyright © 2017 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 `TNLSafeOperation` works to encapsulate fixes for `NSOperation`.

 Specifically:
    - `NSOperation` is supposed to clear the `completionBlock` after it has been called.  It does do this on macOS, but not on all versions of iOS.  `TNLSafeOperation` fixes this.
 */
@interface TNLSafeOperation : NSOperation
@end

NS_ASSUME_NONNULL_END


//
//  TNLTemporaryFile.h
//  TwitterNetworkLayer
//
//  Created on 7/18/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Protocol interface to a temporary file.

 `TNLTemporaryFile` objects have the behavior of opaquely maintaining a temporary file until that
 file is moved to a permanent location.  If the `TNLTemporaryFile` deallocates before its associated
 temporary file is moved to a temporary location, the file will be deleted.

 ## Creating a `TNLTemporaryFile` instance

 Anyone can implement a concrete class that conforms to `TNLTemporaryFile`, but as a convenience a
 function is provided for constructing a concrete `TNLTemporaryFile` too.

    extern id<TNLTemporaryFile> TNLTemporaryFileConstructedFromExistingFile(
                                        NSString * __nonnull filePath,
                                        NSError * __nullable * __nullable errorOut
                                );

 __Arguments:__

 _filePath_: the path to the existing file that you'd like to convert into a temporary file

 _errorOut_: the (optional) output reference to an `NSError` in case an error occurred

 __Return Value:__

 Returns a concreten `TNLTemporaryFile` on success or `nil` on error

 __Note:__

 Calling `TNLTemporaryFileConstructedFromExistingFile` will take ownership of the target file at
 _filePath_.  Once this function is called and succeeds, you may no longer access the file.  The
 underlying implementation details are inconsequential, but effectively the file will be converted
 into a temporary file who's lifespan is governed by the `TNLTemporaryFile` interface.

 @note: `tnl_` method prefixes are not used for `TNLTemporaryFile` since this is just an interface
 to a concrete TNL object and there's no actual need for consuming apps to adopt this protocol.

 */
@protocol TNLTemporaryFile <NSObject>

@required

/**
 Move the temporary file to a permanent location

 @note Will fail on a second call
 @param path  The permanent location to move the temp file to
 @param error The `NSError`, if one occurs
 @return `YES` if moved, `NO` if failed to move and `error` will be populated (if provided)
 */
- (BOOL)moveToPath:(NSString *)path error:(out NSError * __nullable * __nullable)error;

@end

//! See comment on `TNLTemporaryFile`
FOUNDATION_EXTERN id<TNLTemporaryFile> __nullable TNLTemporaryFileConstructedFromExistingFile(NSString *filePath,
                                                                                              NSError * __nullable * __nullable errorOut);

NS_ASSUME_NONNULL_END

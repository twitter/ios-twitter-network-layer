//
//  TAPIUploadMediaRequest.h
//  TNLExample
//
//  Created by Nolan O'Brien on 5/30/18.
//  Copyright © 2018 Twitter. All rights reserved.
//

#import "TAPIRequest.h"
#import "TAPIResponse.h"

@interface TAPIUploadMediaRequest : TAPIRetriableRequest
- (instancetype)initWithImageData:(NSData *)imageData;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface TAPIUploadMediaResponse : TAPIResponse <TAPIActionResponse>
@end

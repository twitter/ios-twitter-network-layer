//
//  TNLXContentEncoding.h
//  TwitterNetworkLayer
//
//  Created on 11/21/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TNLContentEncoder;
@protocol TNLContentDecoder;

@interface TNLXContentEncoding : NSObject

+ (id<TNLContentEncoder>)GZIPContentEncoder;
+ (id<TNLContentDecoder>)GZIPContentDecoder;

+ (id<TNLContentEncoder>)DEFLATEContentEncoder;
+ (id<TNLContentDecoder>)DEFLATEContentDecoder;

+ (id<TNLContentEncoder>)Base64ContentEncoder;
+ (id<TNLContentDecoder>)Base64ContentDecoder;

@end

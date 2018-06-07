//
//  TNLCommunicationAgent_Project.h
//  TwitterNetworkLayer
//
//  Created on 03/29/2018.
//  Copyright © 2018 Twitter. All rights reserved.
//

#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <TwitterNetworkLayer/TNLCommunicationAgent.h>

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_IPHONE

@interface TNLCarrierInfoInternal : NSObject <TNLCarrierInfo>

+ (instancetype)carrierWithCarrier:(id<TNLCarrierInfo>)carrier;

- (instancetype)initWithCarrierName:(NSString *)carrierName
                  mobileCountryCode:(NSString *)mobileCountryCode
                  mobileNetworkCode:(NSString *)mobileNetworkCode
                     isoCountryCode:(NSString *)isoCountryCode
                         allowsVOIP:(BOOL)allowsVOIP;

@end

@interface CTCarrier (TNLCarrierInfo) <TNLCarrierInfo>
@end

FOUNDATION_EXTERN NSDictionary * __nullable TNLCarrierInfoToDictionary(id<TNLCarrierInfo> __nullable carrierInfo);
FOUNDATION_EXTERN id<TNLCarrierInfo> __nullable TNLCarrierInfoFromDictionary(NSDictionary * __nullable dict);

#endif

NS_ASSUME_NONNULL_END

//
//  TNLCommunicationAgent_Project.h
//  TwitterNetworkLayer
//
//  Created on 03/29/2018.
//  Copyright © 2018 Twitter. All rights reserved.
//


#pragma mark Primary import

#import <TwitterNetworkLayer/TNLCommunicationAgent.h>

#if TARGET_OS_IOS && !TARGET_OS_UIKITFORMAC

#pragma mark IOS only imports

#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END

#endif // TARGET_OS_IOS && !TARGET_OS_UIKITFORMAC

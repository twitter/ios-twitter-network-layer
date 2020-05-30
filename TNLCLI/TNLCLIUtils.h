//
//  TNLCLIUtils.h
//  tnlcli
//
//  Created on 9/17/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN BOOL TNLCLIParseColonSeparatedKeyValuePair(NSString *str,
                                                             NSString * __nullable * __nullable keyOut,
                                                             NSString * __nullable * __nullable valueOut);

FOUNDATION_EXTERN NSNumber * __nullable TNLCLINumberValueFromString(NSString *str);
FOUNDATION_EXTERN NSNumber * __nullable TNLCLIBoolNumberValueFromString(NSString *value);

NS_ASSUME_NONNULL_END

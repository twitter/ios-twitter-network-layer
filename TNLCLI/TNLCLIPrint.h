//
//  TNLCLIPrint.h
//  tnlcli
//
//  Created on 9/12/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

#define tnlcli_printf   printf
#define tnlcli_fprintf  fprintf

FOUNDATION_EXTERN void TNLCLIPrintWarning(NSString *warning);
FOUNDATION_EXTERN void TNLCLIPrintError(NSError *error);
FOUNDATION_EXTERN void TNLCLIPrintUsage(NSString * __nullable cliName);

FOUNDATION_EXTERN NSData *TNLCLIEnsureDataIsNullTerminated(NSData *data);


NS_ASSUME_NONNULL_END

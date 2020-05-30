//
//  TNLCLIError.h
//  TNLCLI
//
//  Created on 9/11/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TNLCLIError)
{
    TNLCLIErrorException = -1,
    TNLCLIErrorUnknown = 0,
    TNLCLIErrorEmptyMainFunctionArguments,
    TNLCLIErrorMissingPWDEnvironmentVariable,
    TNLCLIErrorMissingRequestURLArgument,
    TNLCLIErrorInvalidURLArgument,
    TNLCLIErrorArgumentInputFileCannotBeRead,
    TNLCLIErrorJSONParseFailure,
    TNLCLIErrorResponseBodyCannotPrint,
    TNLCLIErrorInvalidRequestConfigurationFileFormat, // needs to be JSON of key=value pairs (all strings, even numeric values!)
};

FOUNDATION_EXTERN NSString * const TNLCLIErrorDomain;

FOUNDATION_EXTERN NSError *TNLCLICreateError(TNLCLIError code, id __nullable userInfoDictionaryOrDescriptionString);

NS_ASSUME_NONNULL_END

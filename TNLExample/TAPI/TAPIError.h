//
//  TAPIError.h
//  TwitterNetworkLayer
//
//  Created on 10/17/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString * const TAPIErrorDomain; // API errors in TAPIResponse object's apiError property
FOUNDATION_EXTERN NSString * const TAPIParseErrorDomain; // errors from parsing the repsonse
FOUNDATION_EXTERN NSString * const TAPIOperationErrorDomain; // errors related to TAPI requests/responses/operations (will be on the response's error property, not API error property)

typedef NS_ENUM(NSInteger, TAPIOperationErrorCode) {
    TAPIOperationErrorCodeUnknown = 0,
    TAPIOperationErrorCodeMissingConsumerCredentials,
    TAPIOperationErrorCodeMissingAccessCredentials,
    TAPIOperationErrorCodeServiceEncounteredTechnicalError,
};

typedef NS_ENUM(NSInteger, TAPIParseErrorCode) {
    TAPIParseErrorCodeCannotParseResponse,
    TAPIParseErrorCodeUnexpectedResponseStructure,
};

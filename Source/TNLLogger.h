//
//  TNLLogger.h
//  TwitterNetworkLayer
//
//  Created on 3/23/16.
//  Copyright © 2016 Twitter. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Syslog compatible log levels for use with *TNLLogger*.
 */
typedef NS_ENUM(NSInteger, TNLLogLevel)
{
    /** Present for syslog compatability */
    TNLLogLevelEmergency,
    /** Present for syslog compatability */
    TNLLogLevelAlert,
    /** Present for syslog compatability */
    TNLLogLevelCritical,
    /** The _ERROR_ log level */
    TNLLogLevelError,
    /** The _WARNING_ log level */
    TNLLogLevelWarning,
    /** Present for syslog compatability */
    TNLLogLevelNotice,
    /** The _INFORMATION_ log level */
    TNLLogLevelInformation,
    /** The _DEBUG_ log level */
    TNLLogLevelDebug
};

/**
 Protocol for supporting log statements from *TwitterNetworkLayer*
 See `[TNLGlobalConfiguration logger]`
 */
@protocol TNLLogger <NSObject>

@required

/**
 Method called when logging a message from *TwitterNetworkLayer*
 */
- (void)tnl_logWithLevel:(TNLLogLevel)level
                 context:(nullable id)context
                    file:(NSString *)file
                function:(NSString *)function
                    line:(int)line
                 message:(NSString *)message;


/*
 Return YES when you want to redact the value of a header field from being logged.

 This method is called when logging all header fields of a request / response,
 abstracted by a `TNLRequestOperation`.
 */
- (BOOL)tnl_shouldRedactHTTPHeaderField:(NSString *)headerField;

@optional

/**
 Optional method to determine if a message should be logged as an optimization to avoid argument
 execution of the log message.

 Default == `YES`
 */
- (BOOL)tnl_canLogWithLevel:(TNLLogLevel)level context:(nullable id)context;

/**
 Optional method to determine if logging should be verbose or not.
 Default == `NO`
 */
- (BOOL)tnl_shouldLogVerbosely;

@end

NS_ASSUME_NONNULL_END

//
//  TNLCLIExecution.m
//  tnlcli
//
//  Created on 9/12/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import <TwitterNetworkLayer/TwitterNetworkLayer.h>

#import "TNLCLIError.h"
#import "TNLCLIExecution.h"
#import "TNLCLIPrint.h"
#import "TNLCLIUtils.h"
#import "TNLGlobalConfiguration+TNLCLI.h"
#import "TNLMutableRequestConfiguration+TNLCLI.h"

#pragma mark - Static Functions

#define FAIL(err) \
({\
    _executionError = (err); \
    TNLCLIPrintError(_executionError); \
    return; \
})
#define SOFT_FAIL(err) \
({\
    NSError *err__ = (err); \
    TNLCLIPrintError(err__); \
    if (!_executionError) { \
        _executionError = err__; \
    } \
})

#pragma mark - TNLCLIExecution

@interface TNLCLIExecution ()
@property (nonatomic, readonly, nullable) NSError *executionError;
@property (nonatomic, readonly, nullable) TNLResponse *response;
- (NSString *)sanitizePath:(NSString *)path;
@end

@interface TNLCLIExecution (TNLDelegate) <TNLRequestDelegate, TNLLogger>
@end

@implementation TNLCLIExecution

- (instancetype)initWithContext:(TNLCLIExecutionContext *)context
{
    if (self = [super init]) {
        _context = context;
        _executionError = context.contextError;
    }
    return self;
}

- (nullable NSError *)execute
{
    @try {
        [self _execute];
    } @catch (NSException *exception) {
        _executionError = TNLCLICreateError(TNLCLIErrorException,
                                            @{
                                                NSDebugDescriptionErrorKey : @"Exception when executing",
                                                @"exception" : exception
                                            });
        TNLCLIPrintError(_executionError);
        tnlcli_fprintf(stderr, "call stack:\n%s\n", exception.callStackSymbols.description.UTF8String);
    }

    return _executionError;
}

- (NSString *)sanitizePath:(NSString *)path
{
    NSString *newPath = [path stringByExpandingTildeInPath];
    if (!newPath.isAbsolutePath) {
        newPath = [self.context.currentDirectory stringByAppendingPathComponent:newPath];
    }
    return newPath;
}

- (void)_execute
{
    if (_executionError) {
        return;
    }

    TNLCLIExecutionContext *context = _context;

    /// Print the version?

    if (context.printVersion) {
        tnlcli_printf("%s version %s\n", context.executableName.UTF8String, [TNLGlobalConfiguration version].UTF8String);
        if (context.requestURLString.length == 0) {
            // just getting the version
            return;
        }
    }

    /// Global Config

    TNLGlobalConfiguration *globalConfig = [TNLGlobalConfiguration sharedInstance];
    globalConfig.assertsEnabled = YES;
    globalConfig.logger = self;
    [globalConfig addAuthenticationChallengeHandler:self];

    // Optionally update global config

    for (NSString *globalConfigSetting in context.globalConfigurations) {
        NSString *name, *value;
        if (TNLCLIParseColonSeparatedKeyValuePair(globalConfigSetting, &name, &value)) {
            (void)[globalConfig tnlcli_applySettingWithName:name value:value];
        } else {
            TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' is not in the expected format for a global configuration: 'name:value'.  Skipping this global configuration.", globalConfigSetting]);
        }
    }

    /// Construct the request

    TNLMutableRequestConfiguration *configuration = nil;
    TNLMutableHTTPRequest *request = nil;

    // Init our request

    request = [[TNLMutableHTTPRequest alloc] initWithURL:[NSURL URLWithString:context.requestURLString]];
    if (!request.URL) {
        FAIL(TNLCLICreateError(TNLCLIErrorInvalidURLArgument,
                               @{
                                   NSDebugDescriptionErrorKey : @"Request URL argument is not valid",
                                   @"url_arg" : context.requestURLString ?: @"<null>"
                               }));
    }

    // Optionally set method

    if (context.requestMethodValueString) {
        request.HTTPMethodValue = TNLHTTPMethodFromString(context.requestMethodValueString);
        if (request.HTTPMethodValue == TNLHTTPMethodGET && ![context.requestMethodValueString isEqualToString:@"GET"]) {
            TNLCLIPrintWarning([NSString stringWithFormat:@"--request-method arg `%s` is not an HTTP Method, using `GET` instead", context.requestMethodValueString.UTF8String]);
        }
    }

    // Optionally set headers

    if (context.requestHeadersFilePath) {
        NSString *filePath = [self sanitizePath:context.requestHeadersFilePath];
        NSData *requestHeadersData = [NSData dataWithContentsOfFile:filePath];
        if (!requestHeadersData) {
            FAIL(TNLCLICreateError(TNLCLIErrorArgumentInputFileCannotBeRead,
                                   @{
                                       NSDebugDescriptionErrorKey : @"--request-headers-file cannot be read",
                                       @"file_arg" : context.requestHeadersFilePath
                                    }));
        }
        NSError *error;
        NSDictionary *headers = [NSJSONSerialization JSONObjectWithData:requestHeadersData options:0 error:&error];
        if (!headers) {
            FAIL(error ?: TNLCLICreateError(TNLCLIErrorUnknown, nil));
        }
        if (![headers isKindOfClass:[NSDictionary class]]) {
            FAIL(TNLCLICreateError(TNLCLIErrorJSONParseFailure,
                                   @{
                                       NSDebugDescriptionErrorKey : @"Failed to parse file's JSON as key-value-pairs",
                                       @"file_arg" : context.requestHeadersFilePath
                                    }));
        }
        request.allHTTPHeaderFields = headers;
    }

    // Optionally set more headers

    for (NSString *header in context.requestHeaders) {
        NSString *field, *value;
        if (TNLCLIParseColonSeparatedKeyValuePair(header, &field, &value)) {
            [request setValue:value forHTTPHeaderField:field];
        } else {
            TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' is not in the expected format for a header: 'Header: Value'.  Skipping this header.", header]);
        }
    }

    // Optionally set body

    if (context.requestBodyFilePath) {
        request.HTTPBodyFilePath = [self sanitizePath:context.requestBodyFilePath];
    }

    // Construct configuration

    if (context.requestConfigurationFilePath) {
        NSString *filePath = [self sanitizePath:context.requestConfigurationFilePath];
        NSError *error;
        configuration = [TNLMutableRequestConfiguration tnlcli_configurationWithFile:filePath error:&error];
        if (!configuration) {
            FAIL(error);
        }
    }

    if (!configuration) {
        configuration = [[TNLMutableRequestConfiguration alloc] init];
    }

    // Optionally update the configuration

    for (NSString *config in context.requestConfigurations) {
        NSString *name, *value;
        if (TNLCLIParseColonSeparatedKeyValuePair(config, &name, &value)) {
            [configuration tnlcli_applySettingWithName:name value:value];
        } else {
            TNLCLIPrintWarning([NSString stringWithFormat:@"'%@' is not in the expected format for a request config seting: 'Name:Value'.  Skipping this setting.", config]);
        }
    }

    /// Run our operation

    TNLRequestOperation *operation = [TNLRequestOperation operationWithRequest:request configuration:configuration delegate:self];
    [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:operation];
    [operation waitUntilFinishedWithoutBlockingRunLoop];

    /// Handle our response

    // Was there an error

    if (_response.operationError) {
        SOFT_FAIL(_response.operationError);
    }

    // Verbose Info

    if (context.verbose) {
        tnlcli_printf("** STATS **\n");
        NSDictionary *metricsDescription = [_response.metrics dictionaryDescription:YES];
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metricsDescription
                                                           options:(NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted)
                                                             error:&error];
        if (jsonData) {
            jsonData = TNLCLIEnsureDataIsNullTerminated(jsonData);
            tnlcli_printf("%s\n", (const char *)jsonData.bytes);
        } else {
            tnlcli_printf("Failed To Generate Stats! ");
            TNLCLIPrintError(error);
        }
    }

    // Response headers

    do {
        NSMutableDictionary *dictionary = [[_response.info allHTTPHeaderFields] mutableCopy];
        dictionary[@"_tnlcli_StatusCode"] = [@(_response.info.statusCode) stringValue];
        dictionary[@"_tnlcli_URL"] = [_response.info.finalURL absoluteString];

        NSError *error;
        NSData *jsonData = (dictionary) ? [NSJSONSerialization dataWithJSONObject:dictionary
                                                                          options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted
                                                                            error:&error] : nil;
        if (!jsonData) {
            SOFT_FAIL(error);
        } else {
            jsonData = TNLCLIEnsureDataIsNullTerminated(jsonData);
            if (context.verbose || [context.responseHeadersOutputModes containsObject:@"print"]) {
                if (context.verbose) {
                    tnlcli_printf("** RESPONSE HEADERS **\n");
                }
                tnlcli_printf("%s\n", (const char *)jsonData.bytes);
            }
            if ([context.responseHeadersOutputModes containsObject:@"file"] && context.requestBodyFilePath) {
                NSString *filePath = [self sanitizePath:context.requestBodyFilePath];
                if (![jsonData writeToFile:filePath options:NSDataWritingAtomic | NSDataWritingWithoutOverwriting error:&error]) {
                    SOFT_FAIL(error);
                }
            }
        }
    } while (0);

    // Response body

    if (_response.info.data || _response.info.temporarySavedFile) {
        NSData *data = _response.info.data;
        BOOL writeToFile = [context.responseBodyOutputModes containsObject:@"file"] && context.responseBodyTargetFilePath;
        const BOOL print = context.verbose || [context.responseBodyOutputModes containsObject:@"print"];
        if (_response.info.temporarySavedFile) {
            NSString *path = nil;
            if (writeToFile) {
                path = [self sanitizePath:context.responseBodyTargetFilePath];
                writeToFile = NO;
            } else if (print) {
                [[NSFileManager defaultManager] createDirectoryAtPath:NSTemporaryDirectory() withIntermediateDirectories:YES attributes:nil error:NULL];
                path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
            }

            if (path) {
                NSError *error;
                if (![_response.info.temporarySavedFile moveToPath:path error:&error]) {
                    SOFT_FAIL(error);
                } else {
                    if (print && !data) {
                        data = [NSData dataWithContentsOfFile:path];
                    }
                }
            }
        }
        if (data) {
            if (writeToFile) {
                NSError *error;
                if (![data writeToFile:[self sanitizePath:context.responseBodyTargetFilePath] options:NSDataWritingAtomic | NSDataWritingWithoutOverwriting error:&error]) {
                    SOFT_FAIL(error);
                }
            }
            if (print) {
                data = TNLCLIEnsureDataIsNullTerminated(data);
                NSString *printable = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (context.verbose) {
                    tnlcli_printf("** RESPONSE BODY **\n");
                }
                if (!printable) {
                    if (context.verbose && ![context.responseBodyOutputModes containsObject:@"print"]) {
                        // due to being verbose
                        tnlcli_printf("Response body is not UTF-8 and cannot be printed.\n");
                    } else {
                        SOFT_FAIL(TNLCLICreateError(TNLCLIErrorResponseBodyCannotPrint, @"The response body is not UTF-8 and therefore cannot be printed"));
                    }
                } else {
                    tnlcli_printf("\r\n%s\n", printable.UTF8String);
                }
            }
        }
    }
}

@end

@implementation TNLCLIExecution (TNLDelegate)

- (void)tnl_logWithLevel:(TNLLogLevel)level
                 context:(nullable id)context
                    file:(NSString *)file
                function:(NSString *)function
                    line:(int)line
                 message:(NSString *)message
{
    static const char * sLevelStrings[] = {
        "EMGCY",
        "ALERT",
        "CRTCL",
        "ERROR",
        "WARNG",
        "Notce",
        "Info ",
        "Debug"
    };
    tnlcli_fprintf((level >= TNLLogLevelNotice) ? stdout : stderr, "%s: %s\n", sLevelStrings[level], message.UTF8String);
}

- (BOOL)tnl_shouldRedactHTTPHeaderField:(NSString *)headerField
{
    return NO;
}

- (BOOL)tnl_canLogWithLevel:(TNLLogLevel)level context:(nullable id)context
{
    if (!_context.verbose) {
        return NO;
    }
    return (level <= TNLLogLevelWarning);
}

- (BOOL)tnl_shouldLogVerbosely
{
    return _context.verbose;
}

- (void)tnl_requestOperation:(TNLRequestOperation *)op didCompleteWithResponse:(TNLResponse *)response
{
    _response = response;
}

- (void)tnl_networkLayerDidReceiveAuthChallenge:(NSURLAuthenticationChallenge *)challenge
                               requestOperation:(TNLRequestOperation *)op
                                     completion:(TNLURLSessionAuthChallengeCompletionBlock)completion
{
    if (self.context.certificateChainDumpDirectory) {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            NSString *host = challenge.protectionSpace.host;
            NSString *dumpDir = [self sanitizePath:self.context.certificateChainDumpDirectory];
            NSFileManager *fm = [NSFileManager defaultManager];
            NSError *error;
            if (![fm createDirectoryAtPath:dumpDir withIntermediateDirectories:YES attributes:nil error:&error]) {
                TNLCLIPrintError(error);
            }

            SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
            const CFIndex chainLength = SecTrustGetCertificateCount(serverTrust);
            if (chainLength > 0 && self.context.verbose) {
                tnlcli_printf("** CERT DUMP **\n");
            }
            for (CFIndex i = 0; i < chainLength; i++) {
                SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
                NSData *DERData = (NSData *)CFBridgingRelease(SecCertificateCopyData(certificate));
                NSString *DERFilePath = [dumpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_cert_%li.DER", host, i]];
                NSString *summary = (NSString *)CFBridgingRelease(CFCopyDescription(certificate));
                if (![DERData writeToFile:DERFilePath options:NSDataWritingWithoutOverwriting error:&error]) {
                    NSMutableDictionary *errorInfo = [error.userInfo mutableCopy] ?: [[NSMutableDictionary alloc] init];
                    errorInfo[@"cert.description"] = summary;
                    TNLCLIPrintError([NSError errorWithDomain:error.domain code:error.code userInfo:errorInfo]);
                } else if (self.context.verbose) {
                    tnlcli_printf("'%s' => %s\n", summary.UTF8String, DERFilePath.UTF8String);
                }
            }
        }
    }

    completion(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end

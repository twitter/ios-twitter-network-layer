//
//  TNLCLIExecutionContext.m
//  TNLCLI
//
//  Created on 9/11/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLCLIError.h"
#import "TNLCLIExecutionContext.h"
#import "TNLCLIPrint.h"

#pragma mark - Static Functions

static NSArray<NSString *> *parseArgs(int argc, const char * argv[])
{
    NSMutableArray<NSString *> *args = [[NSMutableArray alloc] init];
    for (int c = 0; c < argc; c++) {
        [args addObject:@(argv[c])];
    }
    return [args copy];
}

#define FAIL(err) \
({\
    _contextError = (err); \
    TNLCLIPrintError(_contextError); \
    return; \
})
#define SOFT_FAIL(err) \
({\
    NSError *err__ = (err); \
    TNLCLIPrintError(err__); \
    if (!_contextError) { \
        _contextError = err__; \
    } \
})

#pragma mark - TNLCLIExecutionContext

@implementation TNLCLIExecutionContext

#pragma mark Init

- (instancetype)initWithArgC:(int)argc argV:(const char **)argv
{
    NSArray<NSString *> *args = parseArgs(argc, argv);
    return [self initWithArgs:args];
}

- (instancetype)initWithArgs:(NSArray<NSString *> *)args
{
    if (self = [super init]) {
        [self digestArgs:args];
    }
    return self;
}

- (void)digestArgs:(NSArray<NSString *> *)args
{
    if (args.count == 0) {
        FAIL(TNLCLICreateError(TNLCLIErrorEmptyMainFunctionArguments, @"Expected args for main(...) function"));
    }

    NSString *str;
    str = @(getenv("PWD"));
    if (!str) {
        FAIL(TNLCLICreateError(TNLCLIErrorMissingPWDEnvironmentVariable, @"Missing PWD environment variable"));
    } else {
        _currentDirectory = [str stringByExpandingTildeInPath];
    }

    str = args.firstObject;
    if (!str.isAbsolutePath) {
        str = [_currentDirectory stringByAppendingPathComponent:str];
    } else {
        str = [str stringByExpandingTildeInPath];
    }

    _executableName = str.lastPathComponent;
    _executableDirectory = [str stringByDeletingLastPathComponent];

    if (args.count == 1) {
        FAIL(TNLCLICreateError(TNLCLIErrorMissingRequestURLArgument, @"Missing `url` for request (final argument to be passed in)"));
    }

    if (args.count == 2 && [args[1] isEqualToString:@"--version"]) {
        _printVersion = YES;
        return;
    }

    NSMutableArray<NSString *> *headers = [[NSMutableArray alloc] init];
    NSMutableArray<NSString *> *configs = [[NSMutableArray alloc] init];
    NSMutableArray<NSString *> *globals = [[NSMutableArray alloc] init];
    for (NSUInteger i = 1; i < args.count - 1; ) {
        NSString *option = args[i++];

        if ([option isEqualToString:@"--verbose"]) {
            _verbose = YES;
            continue;
        }

        if ([option isEqualToString:@"--version"]) {
            _printVersion = YES;
            continue;
        }

        NSString *value = args[i++];
        if (i == args.count) {
            FAIL(TNLCLICreateError(TNLCLIErrorMissingRequestURLArgument, @"Missing `url` for request (final argument to be passed in)"));
        }

#define CASE(arg, ivar) \
        if ([option isEqualToString: (arg) ]) { \
            ivar = [value copy]; \
            continue; \
        } \

        CASE(@"--request-config-file", _requestConfigurationFilePath);
        CASE(@"--request-headers-file", _requestHeadersFilePath);
        CASE(@"--request-body-file", _requestBodyFilePath);
        CASE(@"--request-method", _requestMethodValueString);

        CASE(@"--response-body-file", _responseBodyTargetFilePath);
        CASE(@"--response-headers-file", _responseHeadersTargetFilePath);
        CASE(@"--dump-cert-chain-directory", _certificateChainDumpDirectory);

        if ([option isEqualToString:@"--request-header"]) {
            [headers addObject:value];
            continue;
        }
        if ([option isEqualToString:@"--request-config"]) {
            [configs addObject:value];
            continue;
        }
        if ([option isEqualToString:@"--global-config"]) {
            [globals addObject:value];
            continue;
        }
        if ([option isEqualToString:@"--response-body-mode"]) {
            _responseBodyOutputModes = [value componentsSeparatedByString:@","];
            continue;
        }
        if ([option isEqualToString:@"--response-headers-mode"]) {
            _responseHeadersOutputModes = [value componentsSeparatedByString:@","];
            continue;
        }

        TNLCLIPrintWarning([NSString stringWithFormat:@"`%@` is an unknown argument.  Skipping it and its value `%@`", option, value]);
#undef CASE
    }
    _requestHeaders = [headers copy];
    _requestConfigurations = [configs copy];
    _globalConfigurations = [globals copy];
    _requestURLString = [args.lastObject copy];
}

@end


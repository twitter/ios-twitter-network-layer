//
//  TNLCLIPrint.m
//  tnlcli
//
//  Created on 9/12/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLCLIPrint.h"

void TNLCLIPrintWarning(NSString *warning)
{
    fprintf(stderr, "WARNING: %s\n", warning.UTF8String);
}

void TNLCLIPrintError(NSError *error)
{
    fprintf(stderr, "ERR: %s:%li %s\n\n", error.domain.UTF8String, error.code, error.userInfo.description.UTF8String ?: "");
}

NSData *TNLCLIEnsureDataIsNullTerminated(NSData *data)
{
    __block BOOL needsNULLTerminator = NO;
    [data enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
        if (byteRange.location + byteRange.length == data.length) {
            const char *cStr = bytes;
            char c = cStr[byteRange.length - 1];
            needsNULLTerminator = (c != '\0');
            *stop = YES;
        }
    }];
    if (needsNULLTerminator) {
        @autoreleasepool {
            NSMutableData *mData = [data mutableCopy];
            [mData appendBytes:"" length:1];
            data = [mData copy];
        }
    }
    return data;
}

void TNLCLIPrintUsage(NSString * __nullable cliName)
{
    // NOTE: when updating the usage, update the README.md too.

    cliName = cliName ?: @"tnlcli";
    tnlcli_fprintf(stderr, "Usage: %s [options] url\n\n", cliName.UTF8String);
    tnlcli_fprintf(stderr, "\tExample: %s --request-method HEAD --response-header-mode file,print --response-header-file response_headers.json https://google.com\n\n", cliName.UTF8String);
    tnlcli_fprintf(stderr, "Argument Options:\n-----------------\n\n");
    tnlcli_fprintf(stderr, "\t--request-config-file <filepath>     TNLRequestConfiguration as a json file\n");
    tnlcli_fprintf(stderr, "\t--request-headers-file <filepath>    json file of key-value-pairs for using as headers\n");
    tnlcli_fprintf(stderr, "\t--request-body-file <filepath>       file for the HTTP body\n");
    tnlcli_fprintf(stderr, "\n");
    tnlcli_fprintf(stderr, "\t--request-header \"Field: Value\"      A header to provide with the request (will override the header if also in the request header file). Can provide multiple headers.\n");
    tnlcli_fprintf(stderr, "\t--request-config \"config: value\"     A config setting for the TNLRequestConfiguration of the request (will override the config if also in the request config file). Can provide multiple configs.\n");
    tnlcli_fprintf(stderr, "\t--request-method <method>            HTTP Method from Section 9 in HTTP/1.1 spec (RFC 2616), such as GET, POST, HEAD, etc\n");
    tnlcli_fprintf(stderr, "\n");
    tnlcli_fprintf(stderr, "\t--response-body-mode <mode>          \"file\" or \"print\" or a combo using commas\n");
    tnlcli_fprintf(stderr, "\t--response-body-file <filepath>      file for the response body to save to (requires \"file\" for --response-body-mode\n");
    tnlcli_fprintf(stderr, "\t--response-headers-mode <mode>       \"file\" or \"print\" or a combo using commas\n");
    tnlcli_fprintf(stderr, "\t--response-headers-file <filepath>   file for the response headers to save to (as json)\n");
    tnlcli_fprintf(stderr, "\n");
    tnlcli_fprintf(stderr, "\t--dump-cert-chain-directory <dir>    directory for the certification chain to be dumped to (as DER files)\n");
    tnlcli_fprintf(stderr, "\n");
    tnlcli_fprintf(stderr, "\t--verbose                            Will print verbose information and force the --response-body-mode and --responde-headers-mode to have \"print\".\n");
    tnlcli_fprintf(stderr, "\t--version                            Will print ther version information.\n");
    tnlcli_fprintf(stderr, "\n");
}


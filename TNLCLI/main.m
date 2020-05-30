//
//  main.m
//  TNLCLI
//
//  Created on 9/11/19.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLCLIExecution.h"
#import "TNLCLIPrint.h"

@import Foundation;

int main(int argc, const char * argv[])
{
    int result = 0;
    @autoreleasepool {

        TNLCLIExecutionContext *context = [[TNLCLIExecutionContext alloc] initWithArgC:argc argV:argv];
        TNLCLIExecution *exe = [[TNLCLIExecution alloc] initWithContext:context];
        NSError *error = [exe execute];
        if (error) {
            TNLCLIPrintUsage(context.executableName);
            result = (int)error.code ?: -1;
        }

    }
    return result;
}

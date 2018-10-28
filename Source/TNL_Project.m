//
//  TNL_Project.m
//  TwitterNetworkLayer
//
//  Created on 5/24/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#include <objc/runtime.h>

#import "TNL_Project.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark Functions

dispatch_source_t tnl_dispatch_timer_create_and_start(dispatch_queue_t queue,
                                                      NSTimeInterval interval,
                                                      NSTimeInterval leeway,
                                                      BOOL repeats,
                                                      dispatch_block_t fireBlock)
{
    dispatch_source_t timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    int64_t repeatInterval = (int64_t)(interval * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(timerSource, dispatch_time(DISPATCH_TIME_NOW, repeatInterval), (repeats) ? (uint64_t)repeatInterval : DISPATCH_TIME_FOREVER, (uint64_t)(leeway * (double)NSEC_PER_SEC));
    dispatch_source_set_event_handler(timerSource, fireBlock);
    dispatch_resume(timerSource);
    return timerSource;
}

NSString *TNLVersion()
{
    TNLStaticAssert(TNL_PROJECT_VERSION >= 1.0 && TNL_PROJECT_VERSION <= 10.0, INVALID_TNL_VERSION);

#define __TNL_VERSION(version) @"" #version
#define _TNL_VERSION(version) __TNL_VERSION( version )
#define TNL_VERSION()  _TNL_VERSION( TNL_PROJECT_VERSION )

    return TNL_VERSION();
}

#pragma mark - Threading

dispatch_queue_t tnl_network_queue()
{
    static dispatch_queue_t sQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sQueue = dispatch_queue_create("tnl.network.queue", DISPATCH_QUEUE_SERIAL);
    });
    return sQueue;
}

dispatch_queue_t tnl_coding_queue()
{
    static dispatch_queue_t sQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sQueue = dispatch_queue_create("tnl.encode.decode.queue", DISPATCH_QUEUE_SERIAL);
    });
    return sQueue;
}

#pragma mark - Dynamic Loading

#if TARGET_OS_IOS || TARGET_OS_TV

Class TNLDynamicUIApplicationClass()
{
    static Class sUIApplicationClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!TNLIsExtension()) {
            sUIApplicationClass = NSClassFromString(@"UIApplication");
            TNLAssert(sUIApplicationClass != Nil);
        }
    });
    return sUIApplicationClass;
}

UIApplication *TNLDynamicUIApplicationSharedApplication()
{
    const Class UIApplicationClass = TNLDynamicUIApplicationClass();
    return UIApplicationClass ? [UIApplicationClass sharedApplication] : nil;
}

#endif // IOS + TV

#pragma mark - Introspection

static BOOL _TNLIntrospection_ObjectImplementsProtocolInstanceMethod(id object,
                                                                     Protocol *p,
                                                                     BOOL avoidRespondsToSelector,
                                                                     BOOL allYesAnyNo);
static BOOL _TNLIntrospection_ObjectImplementsProtocolInstanceMethod(id object,
                                                                     Protocol *p,
                                                                     BOOL avoidRespondsToSelector,
                                                                     BOOL allYesAnyNo)
{
    Class theClass = [object class];
    BOOL hit = allYesAnyNo;
    for (unsigned int loop = NO; loop <= YES && (hit == allYesAnyNo); loop++) {
        unsigned int count = 0;
        struct objc_method_description * methodList = protocol_copyMethodDescriptionList(p, !loop, YES, &count);
        if (count > 0) {
            for (unsigned int i = 0; i < count && (hit == allYesAnyNo); i++) {
                if (avoidRespondsToSelector) {
                    hit = (NULL != class_getInstanceMethod(theClass, methodList[i].name));
                } else {
                    hit = [object respondsToSelector:methodList[i].name];
                }
            }
        }
        free(methodList);
    }
    return hit;
}

NSArray *TNLIntrospection_SelectorsForProtocol(Protocol *p,
                                               BOOL requiredMethods,
                                               BOOL instanceMethods)
{
    NSMutableArray *selectors;
    unsigned int count = 0;
    struct objc_method_description * methodList = protocol_copyMethodDescriptionList(p,
                                                                                     requiredMethods,
                                                                                     instanceMethods,
                                                                                     &count);
    if (count > 0) {

        selectors = [NSMutableArray arrayWithCapacity:count];
        for (unsigned int i = 0; i < count; i++) {
            [selectors addObject:[NSValue valueWithPointer:methodList[i].name]];
        }

    }
    free(methodList);
    return selectors;
}

BOOL TNLIntrospection_ObjectImplementsAnyProtocolInstanceMethod(id object,
                                                                Protocol *p,
                                                                BOOL avoidRespondsToSelector)
{
    return _TNLIntrospection_ObjectImplementsProtocolInstanceMethod(object,
                                                                    p,
                                                                    avoidRespondsToSelector,
                                                                    NO);
}

BOOL TNLIntrospection_ProtocolContainsIntanceMethodSelector(Protocol *p,
                                                            SEL selector)
{
    struct objc_method_description method = protocol_getMethodDescription(p,
                                                                          selector,
                                                                          YES,
                                                                          YES);
    if (method.name != selector) {
        method = protocol_getMethodDescription(p,
                                               selector,
                                               NO,
                                               YES);
    }
    return method.name == selector;
}

BOOL TNLIntrospection_ObjectImplementsAllProtocolInstanceMethods(id object,
                                                                 Protocol *p,
                                                                 BOOL avoidRespondsToSelector)
{
    return _TNLIntrospection_ObjectImplementsProtocolInstanceMethod(object,
                                                                    p,
                                                                    avoidRespondsToSelector,
                                                                    YES);
}

#if DEBUG

// When debugging, it can be useful to note the object counts of certain objects

#ifndef TRACK_OBJECT_COUNTS
#define TRACK_OBJECT_COUNTS 0
#endif

#if TRACK_OBJECT_COUNTS

static NSMutableDictionary *sCounts = nil;
static dispatch_queue_t sCountsQueue = NULL;
static dispatch_source_t sCountsTimer = NULL;

@interface NSObject (DebugSwizzle)
- (void)tnl_dealloc;
- (id)init_TNL;
@end

static void LogConnectCounts(void)
{
    TNLLogDebug(@"TNLCounts", @"\n**********\n\t%@\n**********", sCounts);
}

__attribute__((constructor))
static void ConnLoad(void)
{
    method_exchangeImplementations(class_getInstanceMethod([NSObject class], NSSelectorFromString(@"dealloc")),
                                   class_getInstanceMethod([NSObject class], @selector(tnl_dealloc)));
    method_exchangeImplementations(class_getInstanceMethod([NSObject class], @selector(init)),
                                   class_getInstanceMethod([NSObject class], @selector(init_TNL)));
    sCounts = [NSMutableDictionary dictionary];
    sCountsQueue = dispatch_queue_create("com.twitter.tnl.debug.object.count.queue", DISPATCH_QUEUE_SERIAL);
    sCountsTimer = tnl_dispatch_timer_create_and_start(sCountsQueue, 4.0, 1.0, YES, ^{
        LogConnectCounts();
    });
}

void TNLIncrementObjectCount(Class class)
{
    dispatch_async(sCountsQueue, ^{
        NSString *className = NSStringFromClass(class);
        if (className) {
            NSUInteger count = [sCounts[className] unsignedIntegerValue];
            sCounts[className] = @(count + 1);
        }
    });
}

void TNLDecrementObjectCount(Class class)
{
    dispatch_async(sCountsQueue, ^{
        NSString *className = NSStringFromClass(class);
        if (className) {
            NSUInteger count = [sCounts[className] unsignedIntegerValue];
            TNLAssert(count != 0);
            if (count > 0) {
                sCounts[className] = @(count - 1);
            }
        }
    });
}

@implementation NSObject (DebugSwizzle)

- (void)tnl_dealloc
{
    Class c = [self class];
    if ([NSStringFromClass(c) hasSuffix:@"URLSession"]) {
        TNLDecrementObjectCount(c);
    }
    [self tnl_dealloc];
}

- (id)init_TNL
{
    self = [self init_TNL];
    if (self) {
        Class c = [self class];
        if ([NSStringFromClass(c) hasSuffix:@"URLSession"]) {
            TNLIncrementObjectCount(c);
        }
    }
    return self;
}

@end

#else // !TRACK_OBJECT_COUNTS

void TNLIncrementObjectCount(Class class)
{
}

void TNLDecrementObjectCount(Class class)
{
}

#endif

#endif // DEBUG

NSError *TNLErrorCreateWithCode(TNLErrorCode code)
{
    return TNLErrorCreateWithCodeAndUserInfo(code, nil);
}

NSError *TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCode code,
                                                  NSError * __nullable underlyingError)
{
    return TNLErrorCreateWithCodeAndUserInfo(code, (underlyingError) ? @{ NSUnderlyingErrorKey : underlyingError } : nil);
}

NSError *TNLErrorCreateWithCodeAndUserInfo(TNLErrorCode code,
                                           NSDictionary * __nullable userInfo)
{
    NSString *errorCodeString = TNLErrorCodeToString(code);
    if (errorCodeString) {
        NSMutableDictionary *mUserInfo = [userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
        mUserInfo[TNLErrorCodeStringKey] = errorCodeString;
        userInfo = mUserInfo;
    }
    return [NSError errorWithDomain:TNLErrorDomain code:code userInfo:userInfo];
}

NS_ASSUME_NONNULL_END

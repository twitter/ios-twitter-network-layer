//
//  TNL_Project.h
//  TwitterNetworkLayer
//
//  Created on 5/24/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import "TNL_ProjectCommon.h"
#import "TNLError.h"
#import "TNLInternalKeys.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * NOTE: this header is private to TNL
 */

#pragma mark - Convenience Macros

/**
 These are convenience macros for speeding up the creation of "setters" of mutable objects
 that subclass immutable objects in order to expose the existing propert(y/ies) as mutable

 - (void)setSomeProperty:(id)someProperty
 PROP_RETAIN_ASSIGN_IMP(someProperty);
 */

#define PROP_RETAIN_ASSIGN_IMP(var) \
{ \
    if (_##var != var) { \
        _##var = var; \
    } \
}

#define PROP_COPY_IMP(var) \
{ \
    if (_##var != var) { \
        _##var = [var copy]; \
    } \
}

#define IS_EQUAL_OBJ_PROP_CHECK(self, other, prop) \
do { \
    if (self.prop) { \
        if (![self.prop isEqual:other.prop]) { \
            return NO; \
        } \
    } else if (other.prop) { \
        return NO; \
    } \
} while (0)

#pragma mark - Brotli SDK Check

#define TARGET_SDK_SUPPORTS_BROTLI 0
#if TARGET_OS_IOS
#if defined(__IPHONE_11_0) && (__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_11_0)
#undef TARGET_SDK_SUPPORTS_BROTLI
#define TARGET_SDK_SUPPORTS_BROTLI 1
#endif
#elif TARGET_OS_TV
#if defined(__TVOS_11_0) && (__TV_OS_VERSION_MAX_ALLOWED >= __TVOS_11_0)
#undef TARGET_SDK_SUPPORTS_BROTLI
#define TARGET_SDK_SUPPORTS_BROTLI 1
#endif
#elif TARGET_OS_WATCH
#if defined(__WATCHOS_4_0) && (__WATCH_OS_VERSION_MAX_ALLOWED >= __WATCHOS_4_0)
#undef TARGET_SDK_SUPPORTS_BROTLI
#define TARGET_SDK_SUPPORTS_BROTLI 1
#endif
#elif TARGET_OS_OSX
#if defined(__MAC_10_13) && (__MAC_OS_X_VERSION_MAX_ALLOWED >= __MAC_10_13)
#undef TARGET_SDK_SUPPORTS_BROTLI
#define TARGET_SDK_SUPPORTS_BROTLI 1
#endif
#else
// Unexpected target, assume Brotli supported
#define TARGET_SDK_SUPPORTS_BROTLI 1
#endif

#pragma mark - Version

FOUNDATION_EXTERN NSString *TNLVersion(void);

#pragma mark - GCD Helpers

#define MIN_TIMER_INTERVAL (0.1)

#define TIMER_LEEWAY_WITH_FIRE_INTERVAL(x) MIN((x) / 10.0, 4.0)

FOUNDATION_EXTERN dispatch_source_t tnl_dispatch_timer_create_and_start(dispatch_queue_t queue,
                                                                        NSTimeInterval interval,
                                                                        NSTimeInterval leeway,
                                                                        BOOL repeats,
                                                                        dispatch_block_t fireBlock);

NS_INLINE void tnl_dispatch_timer_invalidate(dispatch_source_t __nullable timerSource)
{
    if (timerSource) {
        dispatch_source_cancel(timerSource);
    }
}

#pragma mark - Threading

FOUNDATION_EXTERN dispatch_queue_t tnl_network_queue(void);
FOUNDATION_EXTERN dispatch_queue_t tnl_coding_queue(void);

#define TNLAssertIsNetworkQueue() TNLAssert(dispatch_queue_get_label(tnl_network_queue()) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))
#define TNLAssertIsCodingQueue() TNLAssert(dispatch_queue_get_label(tnl_coding_queue()) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))

#pragma mark - Dynamic Linking

#if TARGET_OS_IOS || TARGET_OS_TV

NS_ASSUME_NONNULL_END
#import <UIKit/UIApplication.h>
NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN UIApplication * __nullable TNLDynamicUIApplicationSharedApplication(void);
FOUNDATION_EXTERN Class __nullable TNLDynamicUIApplicationClass(void);

#endif // TARGET_OS_IOS || TARGET_OS_TV

#pragma mark - Logging

#ifndef ENABLE_LOG_METHODS
#define ENABLE_LOG_METHODS 0
#endif

#if ENABLE_LOG_METHODS
#define METHOD_LOG() TNLLogDebug(NSStringFromClass([self class]), @"%@", NSStringFromSelector(_cmd))
#else
#define METHOD_LOG() ((void)0)
#endif

#define TNLLogVerboseEnabled() ([gTNLLogger respondsToSelector:@selector(tnl_shouldLogVerbosely)] ? [gTNLLogger tnl_shouldLogVerbosely] : NO)

#pragma mark - Introspection

#if DEBUG
@interface NSObject (Introspection)

// existing private methods on NSObject that can be exposed for debugging purposes

- (null_unspecified id)_shortMethodDescription;  // lists all the instance and class methods of the receiver,
- (null_unspecified id)_methodDescription;       // does the same, including the superclasses' methods,
- (null_unspecified id)_ivarDescription;         // lists all the instance variables of the receiver, their type, and their value.
@end
#endif

/** Returns an array of NSValues.  Each value encapsulates a SEL.  SEL selector = [(NSValue *)selectorsArray[i] pointerValue]; */
FOUNDATION_EXTERN NSArray<NSValue *> * __nullable TNLIntrospection_SelectorsForProtocol(Protocol *p,
                                                                                        BOOL requiredMethods,
                                                                                        BOOL instanceMethods);

/** Returns YES iff the object implements at least one method from the given protocol.  Sometimes, respondsToSelector: can be overridden - provide YES for avoidRespondsToSelector to bypass inspecting the object with that method and use direct introspection instead. */
FOUNDATION_EXTERN BOOL TNLIntrospection_ObjectImplementsAnyProtocolInstanceMethod(id object,
                                                                                  Protocol *p,
                                                                                  BOOL avoidRespondsToSelector);

/** Returns YES iff the protocol contains the given selector as an instance method */
FOUNDATION_EXTERN BOOL TNLIntrospection_ProtocolContainsIntanceMethodSelector(Protocol *p,
                                                                              SEL selector);

/** Returns YES iff the object implements all the protocol instance methods of the provided protocol.  Sometimes, respondsToSelector: can be overridden - provide YES for avoidRespondsToSelector to bypass inspecting the object with that method and use direct introspection instead. */
FOUNDATION_EXTERN BOOL TNLIntrospection_ObjectImplementsAllProtocolInstanceMethods(id object,
                                                                                   Protocol *p,
                                                                                   BOOL avoidRespondsToSelector);

#pragma mark - Debugging Tools

#if DEBUG
// Add this to inits of objects to track
FOUNDATION_EXTERN void TNLIncrementObjectCount(Class class);
// Add this to deallocs of objects to track
FOUNDATION_EXTERN void TNLDecrementObjectCount(Class class);
#else
#define TNLIncrementObjectCount(class) ((void)0)
#define TNLDecrementObjectCount(class) ((void)0)
#endif

#pragma mark - Error Helpers

FOUNDATION_EXTERN NSError *TNLErrorCreateWithCode(TNLErrorCode code);
FOUNDATION_EXTERN NSError *TNLErrorCreateWithCodeAndUnderlyingError(TNLErrorCode code,
                                                                    NSError * __nullable underlyingError);
FOUNDATION_EXTERN NSError *TNLErrorCreateWithCodeAndUserInfo(TNLErrorCode code,
                                                             NSDictionary * __nullable userInfo);

#if TARGET_OS_WATCH
#define kCFErrorDomainCFNetwork @"kCFErrorDomainCFNetwork"
#endif

NS_ASSUME_NONNULL_END

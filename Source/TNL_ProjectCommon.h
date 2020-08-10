//
//  TNL_ProjectCommon.h
//  TwitterNetworkLayer
//
//  Created on 3/5/15.
//  Copyright © 2020 Twitter. All rights reserved.
//

// This header is kept in sync with other *_Common.h headers from sibling projects.
// This header is separate from TNL_Project.h which has TNL specific helper code.

#import <Foundation/Foundation.h>

#import <TwitterNetworkLayer/TNLLogger.h>


NS_ASSUME_NONNULL_BEGIN


#pragma mark - File Name macro

/**
 Helper macro for the file name macro.

 `__FILE__` is the historical C macro that is replaced with the full file path of the current file being compiled (e.g. `/Users/username/workspace/project/source/subfolder/anotherfolder/implementation/file.c`)
 `__FILE_NAME__` is the new C macro in clang that is replaced with the file name of the current file being compiled (e.g. `file.c`)

 By default, if `__FILE_NAME__` is availble with the current compiler, it will be used.
 This behavior can be overridden by providing a value for `TNL_FILE_NAME` to the compiler, like `-DTNL_FILE_NAME=__FILE__` or `-DTNL_FILE_NAME=\"redacted\"`
 */
#if !defined(TNL_FILE_NAME)
#ifdef __FILE_NAME__
#define TNL_FILE_NAME __FILE_NAME__
#else
#define TNL_FILE_NAME __FILE__
#endif
#endif

#pragma mark - Binary

FOUNDATION_EXTERN BOOL TNLIsExtension(void);

#pragma mark - Availability

// macros helpers to match against specific iOS versions and their mapped non-iOS platform versions

#define tnl_available_ios_11    @available(iOS 11, tvOS 11, macOS 10.13, watchOS 4, *)
#define tnl_available_ios_12    @available(iOS 12, tvOS 12, macOS 10.14, watchOS 5, *)
#define tnl_available_ios_13    @available(iOS 13, tvOS 13, macOS 10.15, watchOS 6, *)
#define tip_available_ios_14    @available(iOS 14, tvOS 14, macOS 11.0, watchOS 7, *)

#if TARGET_OS_IOS
#define TNL_OS_VERSION_MAX_ALLOWED_IOS_14 (__IPHONE_OS_VERSION_MAX_ALLOWED >= 140000)
#elif TARGET_OS_MACCATALYST
#define TNL_OS_VERSION_MAX_ALLOWED_IOS_14 (__IPHONE_OS_VERSION_MAX_ALLOWED >= 140000)
#elif TARGET_OS_TV
#define TNL_OS_VERSION_MAX_ALLOWED_IOS_14 (__TV_OS_VERSION_MAX_ALLOWED >= 140000)
#elif TARGET_OS_WATCH
#define TNL_OS_VERSION_MAX_ALLOWED_IOS_14 (__WATCH_OS_VERSION_MAX_ALLOWED >= 70000)
#elif TARGET_OS_OSX
#define TGF_OS_VERSION_MAX_ALLOWED_IOS_14 (__MAC_OS_X_VERSION_MAX_ALLOWED >= 110000)
#else
#warning Unexpected Target Platform
#define TNL_OS_VERSION_MAX_ALLOWED_IOS_14 (0)
#endif

#pragma mark - Bitmask Helpers

/** Does the `mask` have at least 1 of the bits in `flags` set */
#define TNL_BITMASK_INTERSECTS_FLAGS(mask, flags)   (((mask) & (flags)) != 0)
/** Does the `mask` have all of the bits in `flags` set */
#define TNL_BITMASK_HAS_SUBSET_FLAGS(mask, flags)   (((mask) & (flags)) == (flags))
/** Does the `mask` have none of the bits in `flags` set */
#define TNL_BITMASK_EXCLUDES_FLAGS(mask, flags)     (((mask) & (flags)) == 0)

#pragma mark - Assert

FOUNDATION_EXTERN BOOL gTwitterNetworkLayerAssertEnabled;

#if !defined(NS_BLOCK_ASSERTIONS)

#define TNLCAssert(condition, desc, ...) \
do {                \
    __PRAGMA_PUSH_NO_EXTRA_ARG_WARNINGS \
    if (__builtin_expect(!(condition), 0)) {        \
        __TNLAssertTriggering(); \
        NSString *__assert_fn__ = [NSString stringWithUTF8String:__PRETTY_FUNCTION__]; \
        __assert_fn__ = __assert_fn__ ? __assert_fn__ : @"<Unknown Function>"; \
        NSString *__assert_file__ = [NSString stringWithUTF8String:TNL_FILE_NAME]; \
        __assert_file__ = __assert_file__ ? __assert_file__ : @"<Unknown File>"; \
        [[NSAssertionHandler currentHandler] handleFailureInFunction:__assert_fn__ \
                                                                file:__assert_file__ \
                                                          lineNumber:__LINE__ \
                                                         description:(desc), ##__VA_ARGS__]; \
    } \
    __PRAGMA_POP_NO_EXTRA_ARG_WARNINGS \
} while(0)

#else // NS_BLOCK_ASSERTIONS defined

#define TNLCAssert(condition, desc, ...) do {} while (0)

#endif // NS_BLOCK_ASSERTIONS not defined

#define TNLAssert(expression) \
({ if (gTwitterNetworkLayerAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); (void)__expressionValue; \
    TNLCAssert(__expressionValue, @"assertion failed: (" #expression ")"); \
} })

#define TNLAssertMessage(expression, format, ...) \
({ if (gTwitterNetworkLayerAssertEnabled) { \
    const BOOL __expressionValue = !!(expression); (void)__expressionValue; \
    TNLCAssert(__expressionValue, @"assertion failed: (" #expression ") message: %@", [NSString stringWithFormat:format, ##__VA_ARGS__]); \
} })

#define TNLAssertNever()      TNLAssert(0 && "this line should never get executed" )

#pragma twitter startignoreformatting

// NOTE: TNLStaticAssert's msg argument should be valid as a variable.  That is, composed of ASCII letters, numbers and underscore characters only.
#define __TNLStaticAssert(line, msg) TNLStaticAssert_##line##_##msg
#define _TNLStaticAssert(line, msg) __TNLStaticAssert( line , msg )

#define TNLStaticAssert(condition, msg) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wunused\"") \
typedef char _TNLStaticAssert( __LINE__ , msg ) [ (condition) ? 1 : -1 ] \
_Pragma("clang diagnostic pop" )

#pragma twitter endignoreformatting

#pragma mark - Logging

FOUNDATION_EXTERN id<TNLLogger> __nullable gTNLLogger;

#pragma twitter startignorestylecheck

#define TNLLog(level, ...) \
do { \
    id<TNLLogger> const __logger = gTNLLogger; \
    TNLLogLevel const __level = (level); \
    if (__logger && (![__logger respondsToSelector:@selector(tnl_canLogWithLevel:context:)] || [__logger tnl_canLogWithLevel:__level context:nil])) { \
        [__logger tnl_logWithLevel:__level context:nil file:@(TNL_FILE_NAME) function:@(__FUNCTION__) line:__LINE__ message:[NSString stringWithFormat: __VA_ARGS__ ]]; \
    } \
} while (0)

#define TNLLogError(...)        TNLLog(TNLLogLevelError, __VA_ARGS__)
#define TNLLogWarning(...)      TNLLog(TNLLogLevelWarning, __VA_ARGS__)
#define TNLLogInformation(...)  TNLLog(TNLLogLevelInformation, __VA_ARGS__)
#define TNLLogDebug(...)        TNLLog(TNLLogLevelDebug, __VA_ARGS__)

#pragma twitter endignorestylecheck

#pragma mark - Debugging Tools

#if DEBUG
FOUNDATION_EXTERN void __TNLAssertTriggering(void);
FOUNDATION_EXTERN BOOL TNLIsDebuggerAttached(void);
FOUNDATION_EXTERN void TNLTriggerDebugSTOP(void);
FOUNDATION_EXTERN BOOL TNLIsDebugSTOPOnAssertEnabled(void);
FOUNDATION_EXTERN void TNLSetDebugSTOPOnAssertEnabled(BOOL stopOnAssert);
#else
#define __TNLAssertTriggering() ((void)0)
#define TNLIsDebuggerAttached() (NO)
#define TNLTriggerDebugSTOP() ((void)0)
#define TNLIsDebugSTOPOnAssertEnabled() (NO)
#define TNLSetDebugSTOPOnAssertEnabled(stopOnAssert) ((void)0)
#endif

FOUNDATION_EXTERN BOOL TNLAmIBeingUnitTested(void);

#pragma mark - Style Check support


#pragma mark - Thread Sanitizer

// Macro to disable the thread-sanitizer for a particular method or function

#if defined(__has_feature)
# if __has_feature(thread_sanitizer)
#  define TNL_THREAD_SANITIZER_DISABLED __attribute__((no_sanitize("thread")))
# else
#  define TNL_THREAD_SANITIZER_DISABLED
# endif
#endif


#pragma mark - Objective-C attribute support

#if defined(__has_attribute) && (defined(__IPHONE_14_0) || defined(__MAC_10_16) || defined(__MAC_11_0) || defined(__TVOS_14_0) || defined(__WATCHOS_7_0))
# define TNL_SUPPORTS_OBJC_DIRECT __has_attribute(objc_direct)
#else
# define TNL_SUPPORTS_OBJC_DIRECT 0
#endif

#if defined(__has_attribute)
# define TNL_SUPPORTS_OBJC_FINAL  __has_attribute(objc_subclassing_restricted)
#else
# define TNL_SUPPORTS_OBJC_FINAL  0
#endif

#pragma mark - Objective-C Direct Support

#if TNL_SUPPORTS_OBJC_DIRECT
# define tnl_nonatomic_direct     nonatomic,direct
# define tnl_atomic_direct        atomic,direct
# define TNL_OBJC_DIRECT          __attribute__((objc_direct))
# define TNL_OBJC_DIRECT_MEMBERS  __attribute__((objc_direct_members))
#else
# define tnl_nonatomic_direct     nonatomic
# define tnl_atomic_direct        atomic
# define TNL_OBJC_DIRECT
# define TNL_OBJC_DIRECT_MEMBERS
#endif // #if TNL_SUPPORTS_OBJC_DIRECT

#pragma mark - Objective-C Final Support

#if TNL_SUPPORTS_OBJC_FINAL
# define TNL_OBJC_FINAL   __attribute__((objc_subclassing_restricted))
#else
# define TNL_OBJC_FINAL
#endif // #if TNL_SUPPORTS_OBJC_FINAL

#pragma mark - tnl_defer support

typedef void(^tnl_defer_block_t)(void);
NS_INLINE void tnl_deferFunc(__strong tnl_defer_block_t __nonnull * __nonnull blockRef)
{
    tnl_defer_block_t actualBlock = *blockRef;
    actualBlock();
}

#define _tnl_macro_concat(a, b) a##b
#define tnl_macro_concat(a, b) _tnl_macro_concat(a, b)

#pragma twitter startignorestylecheck

#define tnl_defer(deferBlock) \
__strong tnl_defer_block_t tnl_macro_concat(tnl_stack_defer_block_, __LINE__) __attribute__((cleanup(tnl_deferFunc), unused)) = deferBlock

#define TNLDeferRelease(ref) tnl_defer(^{ if (ref) { CFRelease(ref); } })

#pragma twitter endignorestylecheck

#pragma mark - GCD helpers

// Autoreleasing dispatch functions.
// callers cannot use autoreleasing passthrough
//
//  Example of what can't be done (autoreleasing passthrough):
//
//      - (void)deleteFile:(NSString *)fileToDelete
//                   error:(NSError * __autoreleasing *)error
//      {
//          tnl_dispatch_sync_autoreleasing(_config.queueForDiskCaches, ^{
//              [[NSFileManager defaultFileManager] removeItemAtPath:fileToDelete
//       /* will lead to crash if set to non-nil value --> */  error:error];
//          });
//      }
//
//  Example of how to avoid passthrough crash:
//
//      - (void)deleteFile:(NSString *)fileToDelete
//                   error:(NSError * __autoreleasing *)error
//      {
//          __block NSError *outerError = nil;
//          tnl_dispatch_sync_autoreleasing(_config.queueForDiskCaches, ^{
//              NSError *innerError = nil;
//              [[NSFileManager defaultFileManager] removeItemAtPath:fileToDelete
//                                                             error:&innerError];
//              outerError = innerError;
//          });
//          if (error) {
//              *error = outerError;
//          }
//      }

// Should pretty much ALWAYS use this for async dispatch
NS_INLINE void tnl_dispatch_async_autoreleasing(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_async(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

// Should pretty much ALWAYS use this for async barrier dispatch
NS_INLINE void tnl_dispatch_barrier_async_autoreleasing(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_barrier_async(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

// Only need this in a tight loop, existing autorelease pool will take effect for dispatch_sync
NS_INLINE void tnl_dispatch_sync_autoreleasing(dispatch_queue_t __attribute__((noescape)) queue, dispatch_block_t block)
{
    dispatch_sync(queue, ^{
        @autoreleasepool {
            block();
        }
    });
}

NS_ASSUME_NONNULL_END



//
//  TNLRequestRetryPolicyConfiguration.m
//  TwitterNetworkLayer
//
//  Created on 5/26/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import "TNL_Project.h"
#import "TNLRequest.h"
#import "TNLRequestOperation.h"
#import "TNLRequestRetryPolicyConfiguration.h"
#import "TNLResponse.h"

NS_ASSUME_NONNULL_BEGIN

static NSArray<NSString *> * _GenerateMethodStrings(NSUInteger methodMask);
static NSUInteger _GenerateMethodMask(NSArray * __nullable methods);
static NSMutableIndexSet * _GenerateStatusCodes(NSArray<NSNumber *> * __nullable statusCodes);
static NSMutableIndexSet * _GenerateURLErrorCodes(NSArray<NSNumber *> * __nullable URLErrorCodes);

static NSMutableIndexSet * _GeneratePOSIXErrorCodes(NSArray<NSNumber *> * __nullable POSIXErrorCodes);

NS_INLINE NSUInteger _POSIXErrorCodeToIndex(int code)
{
    return (NSUInteger)code;
}

//NS_INLINE int _POSIXErrorCodeFromIndex(NSUInteger index)
//{
//    return (int)index;
//}

NS_INLINE NSUInteger _URLErrorCodeToIndex(NSInteger code)
{
    // NSURL error codes are all negative values
    // But we'll store in a postive index set
    if (code < 0) {
        code *= -1;
    }
    return (NSUInteger)code;
}

//NS_INLINE NSInteger _URLErrorCodeFromIndex(NSUInteger index)
//{
//    const NSInteger codeInt = (NSInteger)index;
//    return codeInt * -1;
//}

NS_INLINE NSUInteger _HTTPStatusCodeToIndex(TNLHTTPStatusCode code)
{
    return (NSUInteger)code;
}

@interface TNLRequestRetryPolicyConfiguration ()

@property (nonatomic, readonly, nullable) NSIndexSet *POSIXErrorCodes;
@property (nonatomic, readonly, nullable) NSIndexSet *URLErrorCodes;
@property (nonatomic, readonly, nullable) NSIndexSet *statusCodes;
@property (nonatomic, readonly) NSUInteger methodMask;

- (instancetype)initWithMethodMask:(NSUInteger)methodMask
                       statusCodes:(nullable NSIndexSet *)statusCodes
                     URLErrorCodes:(nullable NSIndexSet *)URLErrorCodes
                   POSIXErrorCodes:(nullable NSIndexSet *)POSIXErrorCodes;

+ (BOOL)tnl_isMutableClass;

@end

@implementation TNLRequestRetryPolicyConfiguration
{
    @protected
    NSUInteger _methodMask;
    NSIndexSet *_statusCodes;
    NSIndexSet *_URLErrorCodes;
    NSIndexSet *_POSIXErrorCodes;
}

@synthesize methodMask = _methodMask;
@synthesize statusCodes = _statusCodes;
@synthesize URLErrorCodes = _URLErrorCodes;
@synthesize POSIXErrorCodes = _POSIXErrorCodes;

+ (BOOL)tnl_isMutableClass
{
    return NO;
}

+ (instancetype)defaultConfiguration
{
    return [[self alloc] initWithRetriableMethods:@[@"GET"]
                                      statusCodes:@[@503]
                                    URLErrorCodes:nil
                                  POSIXErrorCodes:nil];
}

+ (instancetype)standardConfiguration
{
    return [[self alloc] initWithRetriableMethods:@[@"GET"]
                                      statusCodes:@[@503]
                                    URLErrorCodes:TNLStandardRetriableURLErrorCodes()
                                  POSIXErrorCodes:TNLStandardRetriablePOSIXErrorCodes()];
}

- (instancetype)initWithRetriableMethods:(nullable NSArray *)methods
                             statusCodes:(nullable NSArray<NSNumber *> *)statusCodes
                           URLErrorCodes:(nullable NSArray<NSNumber *> *)URLErrorCodes
                         POSIXErrorCodes:(nullable NSArray<NSNumber *> *)POSIXErrorCodes
{
    return [self initWithMethodMask:_GenerateMethodMask(methods)
                        statusCodes:_GenerateStatusCodes(statusCodes)
                      URLErrorCodes:_GenerateURLErrorCodes(URLErrorCodes)
                    POSIXErrorCodes:_GeneratePOSIXErrorCodes(POSIXErrorCodes)];
}

- (instancetype)initWithAllMethodsRetriableAndRetriableStatusCodes:(nullable NSArray<NSNumber *> *)statusCodes URLErrorCodes:(nullable NSArray<NSNumber *> *)URLErrorCodes POSIXErrorCodes:(nullable NSArray<NSNumber *> *)POSIXErrorCodes
{
    return [self initWithMethodMask:NSUIntegerMax
                        statusCodes:_GenerateStatusCodes(statusCodes)
                      URLErrorCodes:_GenerateURLErrorCodes(URLErrorCodes)
                    POSIXErrorCodes:_GeneratePOSIXErrorCodes(POSIXErrorCodes)];
}

- (instancetype)initWithMethodMask:(NSUInteger)methodMask
                       statusCodes:(nullable NSIndexSet *)statusCodes
                     URLErrorCodes:(nullable NSIndexSet *)URLErrorCodes
                   POSIXErrorCodes:(nullable NSIndexSet *)POSIXErrorCodes
{
    // Internal only method so we will just assign/retain instead of copy
    if (self = [super init]) {
        _methodMask = methodMask;

        const BOOL mutable = [[self class] tnl_isMutableClass];
        _statusCodes = (mutable) ? [statusCodes mutableCopy] : [statusCodes copy];
        _URLErrorCodes = (mutable) ? [URLErrorCodes mutableCopy] : [URLErrorCodes copy];
        _POSIXErrorCodes = (mutable) ? [POSIXErrorCodes mutableCopy] : [POSIXErrorCodes copy];
    }
    return self;
}

- (instancetype)init
{
    return [self initWithMethodMask:0 statusCodes:nil URLErrorCodes:nil POSIXErrorCodes:nil];
}

- (BOOL)methodCanBeRetried:(TNLHTTPMethod)method
{
    const NSUInteger mask = (1 << method);
    return TNL_BITMASK_HAS_SUBSET_FLAGS(self.methodMask, mask);
}

- (BOOL)statusCodeCanBeRetried:(TNLHTTPStatusCode)code
{
    return [self.statusCodes containsIndex:_HTTPStatusCodeToIndex(code)];
}

- (BOOL)URLErrorCodeCanBeRetried:(NSInteger)code
{
    return [self.URLErrorCodes containsIndex:_URLErrorCodeToIndex(code)];
}

- (BOOL)POSIXErrorCodeCanBeRetried:(int)code
{
    return [self.POSIXErrorCodes containsIndex:_POSIXErrorCodeToIndex(code)];
}

- (BOOL)requestCanBeRetriedForResponse:(TNLResponse *)response
{
    TNLResponseInfo *info = response.info;

    // check if the method can be retried

    if (![self methodCanBeRetried:[TNLRequest HTTPMethodValueForRequest:info.finalURLRequest]]) {
        return NO;
    }

    // can we retry this status code?

    if ([self statusCodeCanBeRetried:info.statusCode]) {
        return YES;
    }

    // was there an error?

    NSError *error = response.operationError;
    if (error) {

        // can we retry this error?

        if ([self _tnl_errorCanBeRetried:error]) {
            return YES;
        }
    }

    // can't retry
    return NO;
}

- (BOOL)_tnl_errorCanBeRetried:(NSError *)error
{
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        if ([self URLErrorCodeCanBeRetried:error.code]) {
            return YES;
        }
    } else if ([error.domain isEqualToString:NSPOSIXErrorDomain]) {
        if ([self POSIXErrorCodeCanBeRetried:(int)error.code]) {
            return YES;
        }
    }

    return NO;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    return [[TNLMutableRequestRetryPolicyConfiguration allocWithZone:zone]
            initWithMethodMask:self.methodMask
            statusCodes:self.statusCodes
            URLErrorCodes:self.URLErrorCodes
            POSIXErrorCodes:self.POSIXErrorCodes];
}

- (NSString *)description
{
    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
    if (self.statusCodes) {
        info[@"HTTPStatusCodes"] = self.statusCodes;
    }
    if (self.URLErrorCodes) {
        info[@"URLErrorCodes"] = self.URLErrorCodes;
    }
    if (self.POSIXErrorCodes) {
        info[@"POSIXErrorCodes"] = self.POSIXErrorCodes;
    }
    if (self.methodMask) {
        info[@"HTTPMethods"] = _GenerateMethodStrings(self.methodMask);
    }
    return [NSString stringWithFormat:@"<%@ %p: %@>", NSStringFromClass([self class]), self, info];
}

@end

@implementation TNLMutableRequestRetryPolicyConfiguration

+ (BOOL)tnl_isMutableClass
{
    return YES;
}

- (void)setMethod:(TNLHTTPMethod)method canBeRetried:(BOOL)canRetry
{
    if (canRetry) {
        _methodMask |= (1 << method);
    } else {
        _methodMask &= ~(1 << method);
    }
}

- (void)setStatusCode:(TNLHTTPStatusCode)code canBeRetried:(BOOL)canRetry
{
    if (!_statusCodes) {
        _statusCodes = [[NSMutableIndexSet alloc] init];
    }
    TNLAssert([_statusCodes isKindOfClass:[NSMutableIndexSet class]]);
    if (canRetry) {
        [(NSMutableIndexSet *)_statusCodes addIndex:_HTTPStatusCodeToIndex(code)];
    } else {
        [(NSMutableIndexSet *)_statusCodes removeIndex:_HTTPStatusCodeToIndex(code)];
    }
}

- (void)setURLErrorCode:(NSInteger)code canBeRetried:(BOOL)canRetry
{
    if (!_URLErrorCodes) {
        _URLErrorCodes = [[NSMutableIndexSet alloc] init];
    }
    TNLAssert([_URLErrorCodes isKindOfClass:[NSMutableIndexSet class]]);
    if (canRetry) {
        [(NSMutableIndexSet *)_URLErrorCodes addIndex:_URLErrorCodeToIndex(code)];
    } else {
        [(NSMutableIndexSet *)_URLErrorCodes removeIndex:_URLErrorCodeToIndex(code)];
    }
}

- (void)setPOSIXErrorCode:(int)code canBeRetried:(BOOL)canRetry
{
    if (!_POSIXErrorCodes) {
        _POSIXErrorCodes = [[NSMutableIndexSet alloc] init];
    }
    TNLAssert([_POSIXErrorCodes isKindOfClass:[NSMutableIndexSet class]]);
    if (canRetry) {
        [(NSMutableIndexSet *)_POSIXErrorCodes addIndex:_POSIXErrorCodeToIndex(code)];
    } else {
        [(NSMutableIndexSet *)_POSIXErrorCodes removeIndex:_POSIXErrorCodeToIndex(code)];
    }
}

- (void)setMethodsThatCanBeRetried:(nullable NSArray *)methods
{
    _methodMask = _GenerateMethodMask(methods);
}

- (void)setStatusCodesThatCanBeRetried:(nullable NSArray<NSNumber *> *)codes
{
    _statusCodes = _GenerateStatusCodes(codes);
}

- (void)setURLErrorCodesThatCanBeRetried:(nullable NSArray<NSNumber *> *)codes
{
    _URLErrorCodes = _GenerateURLErrorCodes(codes);
}

- (void)setPOSIXErrorCodesThatCanBeRetried:(nullable NSArray<NSNumber *> *)codes
{
    _POSIXErrorCodes = _GeneratePOSIXErrorCodes(codes);
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return [[TNLRequestRetryPolicyConfiguration allocWithZone:zone] initWithMethodMask:self.methodMask
                                                                           statusCodes:self.statusCodes
                                                                         URLErrorCodes:self.URLErrorCodes
                                                                       POSIXErrorCodes:self.POSIXErrorCodes];
}

@end

static NSArray<NSString *> *_GenerateMethodStrings(NSUInteger methodMask)
{
    NSMutableArray<NSString *> *methods = [[NSMutableArray alloc] init];
    // OPTIONS == min
    // CONNECT == max
    for (TNLHTTPMethod method = TNLHTTPMethodOPTIONS; methodMask != 0 && method <= TNLHTTPMethodCONNECT; method++) {
        if (0x1 & methodMask) {
            NSString *methodString = TNLHTTPMethodToString(method);
            if (methodString) {
                [methods addObject:methodString];
            }
        }
        methodMask >>= 1;
    }
    return methods;
}

static NSUInteger _GenerateMethodMask(NSArray * __nullable methods)
{
    NSUInteger newMask = 0;
    for (id methodObj in methods) {
        TNLHTTPMethod method = TNLHTTPMethodUnknown;
        if ([methodObj isKindOfClass:[NSString class]]) {
            method = TNLHTTPMethodFromString(methodObj);
        } else if ([methodObj isKindOfClass:[NSNumber class]]) {
            method = [methodObj integerValue];
            if (!TNLHTTPMethodToString([methodObj integerValue])) {
                method = TNLHTTPMethodUnknown;
            }
        }
        if (method != TNLHTTPMethodUnknown) {
            newMask |= (1 << method);
        }
    }
    return newMask;
}

static NSMutableIndexSet *_GenerateStatusCodes(NSArray * __nullable statusCodes)
{
    NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];
    for (NSNumber *code in statusCodes) {
        if ([code isKindOfClass:[NSNumber class]]) {
            [indexSet addIndex:code.unsignedIntegerValue];
        }
    }
    return indexSet;
}

static NSMutableIndexSet *_GenerateURLErrorCodes(NSArray * __nullable URLErrorCodes)
{
    NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];
    for (NSNumber *code in URLErrorCodes) {
        if ([code isKindOfClass:[NSNumber class]]) {
            [indexSet addIndex:_URLErrorCodeToIndex(code.integerValue)];
        }
    }
    return indexSet;
}

static NSMutableIndexSet *_GeneratePOSIXErrorCodes(NSArray * __nullable POSIXErrorCodes)
{
    NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];
    for (NSNumber *code in POSIXErrorCodes) {
        if ([code isKindOfClass:[NSNumber class]]) {
            [indexSet addIndex:_POSIXErrorCodeToIndex(code.intValue)];
        }
    }
    return indexSet;
}

NS_ASSUME_NONNULL_END

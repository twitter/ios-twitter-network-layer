//
//  TNLResponse.m
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <mach/mach_time.h>

#import "NSCoder+TNLAdditions.h"
#import "NSDictionary+TNLAdditions.h"
#import "NSURLResponse+TNLAdditions.h"
#import "NSURLSessionTaskMetrics+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLAttemptMetaData.h"
#import "TNLAttemptMetrics_Project.h"
#import "TNLHTTP.h"
#import "TNLRequest.h"
#import "TNLResponse_Project.h"
#import "TNLTemporaryFile_Project.h"
#import "TNLTiming.h"

@implementation TNLResponse

@synthesize operationError = _operationError;
@synthesize originalRequest = _originalRequest;
@synthesize info = _info;
@synthesize metrics = _metrics;

+ (instancetype)responseWithResponse:(TNLResponse *)response
{
    TNLResponse *newResponse = [[[self class] alloc] initInternalWithRequest:response.originalRequest
                                                              operationError:response.operationError
                                                                        info:response.info
                                                                     metrics:response.metrics];
    [newResponse prepare];
    return newResponse;
}

+ (instancetype)responseWithRequest:(id<TNLRequest>)originalRequest
                     operationError:(NSError *)operationError
                               info:(TNLResponseInfo *)info
                            metrics:(TNLResponseMetrics *)metrics
{
    TNLResponse *response = [[[self class] alloc] initInternalWithRequest:originalRequest
                                                           operationError:operationError
                                                                     info:info
                                                                  metrics:metrics];
    [response prepare];
    [metrics finalizeMetrics];
    return response;
}

- (instancetype)initInternalWithRequest:(id<TNLRequest>)originalRequest
                         operationError:(NSError *)operationError
                                   info:(TNLResponseInfo *)info
                                metrics:(TNLResponseMetrics *)metrics
{
    if (self = [super init]) {
        _originalRequest = [originalRequest conformsToProtocol:@protocol(NSCopying)] ?
                                [(NSObject *)originalRequest copy] :
                                originalRequest;
        _operationError = operationError;
        _info = info;
        _metrics = metrics;
    }
    return self;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
    return nil;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    NSError *operationError = [aDecoder decodeObjectOfClass:[NSError class]
                                                     forKey:@"operationError"];
    TNLResponseInfo *info = [aDecoder decodeObjectOfClass:[TNLResponseInfo class]
                                                   forKey:@"info"];
    TNLResponseMetrics *metrics = [aDecoder decodeObjectOfClass:[TNLResponseMetrics class]
                                                         forKey:@"metrics"];

    id<TNLRequest> request = nil;
    {
        NSString *originalRequestClassName = [aDecoder decodeObjectOfClass:[NSString class]
                                                                    forKey:@"originalRequestClass"];
        Class originalRequestClass = Nil;
        if (originalRequestClassName != nil) {
            // we have an archived "request class name", try to convert into a concrete class to decode

            // does the decoder support "class name to class" mapping?
            if ([aDecoder respondsToSelector:@selector(classForClassName:)]) {
                // has mapping support, load via mapping
                originalRequestClass = [(id)aDecoder classForClassName:originalRequestClassName];
            }
            // did we not load a mapping and have a class level mapping?
            if (Nil == originalRequestClass && [[aDecoder class] respondsToSelector:@selector(classForClassName:)]) {
                // has class level mapping support, load via mapping
                originalRequestClass = [[aDecoder class] classForClassName:originalRequestClassName];
            }
            // did we not load via any mappings?
            if (Nil == originalRequestClass) {
                // load directly via NSClassFromString
                originalRequestClass = NSClassFromString(originalRequestClassName);
            }
        }

        // If we have a class...
        if (originalRequestClass != Nil) {
            // ... try to decode the request
            request = [aDecoder decodeObjectOfClass:originalRequestClass
                                             forKey:@"originalRequest"];
        }
    }

    self = [self initInternalWithRequest:request
                          operationError:operationError
                                    info:info
                                 metrics:metrics];
    if (self) {
        [self prepare];
        [metrics finalizeMetrics];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:TNLErrorToSecureCodingError(_operationError) forKey:@"operationError"];
    [aCoder encodeObject:_info forKey:@"info"];
    [aCoder encodeObject:_metrics forKey:@"metrics"];

    id<TNLRequest, NSSecureCoding> originalRequest = nil;
    if ([_originalRequest conformsToProtocol:@protocol(NSSecureCoding)] && [[_originalRequest class] supportsSecureCoding]) {
        originalRequest = (id<TNLRequest, NSSecureCoding>)_originalRequest;
    } else {
        originalRequest = [[TNLResponseEncodedRequest alloc] initWithSourceRequest:_originalRequest];
    }
    [aCoder encodeObject:NSStringFromClass([originalRequest class]) forKey:@"originalRequestClass"];
    [aCoder encodeObject:originalRequest forKey:@"originalRequest"];
}

- (void)prepare
{
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (NSString *)description
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p {", NSStringFromClass([self class]), self];

    NSString *requestDescription = nil;
    if (self.originalRequest) {
        if ([self.originalRequest respondsToSelector:@selector(URL)]) {
            requestDescription = [[self.originalRequest URL] description];
        } else {
            requestDescription = NSStringFromClass([self.originalRequest class]);
        }
    }
    [description appendFormat:@" Request: %@", requestDescription];

    [description appendFormat:@", HTTP: %ld", (long)self.info.statusCode];

    if (self.operationError) {
        [description appendFormat:@", Operation-Error: %@", self.operationError];
    }

    if (self.info.source == TNLResponseSourceLocalCache) {
        [description appendString:@", Cache-Hit: YES"];
    }

    if (self.metrics) {
        [description appendFormat:@", Metrics: %@", self.metrics];
    }

    [description appendString:@" }>"];
    return description;
}

- (NSUInteger)hash
{
    return (NSUInteger)((NSInteger)self.operationError.domain.hash + self.operationError.code) +
           self.info.hash +
           self.metrics.hash; // ignore the original request hash
}

- (BOOL)isEqual:(id)object
{
    if ([super isEqual:object]) {
        return YES;
    }

    TNLResponse *other = object;
    if (![other isKindOfClass:[TNLResponse class]]) {
        return NO;
    }

    if (!TNLSecureCodingErrorsAreEqual(self.operationError, other.operationError)) {
        return NO;
    }

    if (self.originalRequest != nil) {
        if ([self.originalRequest respondsToSelector:@selector(isEqualToRequest:)]) {
            if (![self.originalRequest isEqualToRequest:other.originalRequest]) {
                return NO;
            }
        } else {
            if (![TNLRequest isRequest:self.originalRequest equalTo:other.originalRequest quickBodyComparison:YES]) {
                return NO;
            }
        }
    } else if (other.originalRequest != nil) {
        return NO;
    }

    IS_EQUAL_OBJ_PROP_CHECK(self, other, info);
    IS_EQUAL_OBJ_PROP_CHECK(self, other, metrics);

    return YES;
}

@end

@implementation TNLResponseInfo
{
    @protected
    NSString *_rawRetryAfterValue;
    id _parsedRetryAfterValue;
    NSDate *_retryAfterDate;
    NSDictionary *_cachedLowercaseHeaderFields;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initWithFinalURLRequest:(NSURLRequest *)finalURLRequest
                            URLResponse:(NSHTTPURLResponse *)URLResponse
                                 source:(TNLResponseSource)source
                                   data:(NSData *)data
                     temporarySavedFile:(id<TNLTemporaryFile>)temporarySavedFile
{
    if (self = [super init]) {
        _URLResponse = URLResponse;
        _finalURLRequest = [finalURLRequest copy];
        _data = data;
        _temporarySavedFile = temporarySavedFile;
        _source = source;
        _cachedLowercaseHeaderFields = [URLResponse.allHeaderFields tnl_copyWithLowercaseKeys];
        {
            // We want to precache the retry after date on construction.
            // This is because the "Retry-After" header could provide a "delay from now" value (in seconds)
            // which we'll want to apply to the current time ([NSDate dateWithTimeIntervalSinceNow:retryAfterDelayInSecondsInteger])
            // and not some future time.
            (void)self.retryAfterDate;
        }
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    NSHTTPURLResponse *URLResponse = [aDecoder decodeObjectOfClass:[NSURLResponse class]
                                                            forKey:@"URLResponse"];
    NSURLRequest *URLRequest = [aDecoder decodeObjectOfClass:[NSURLRequest class]
                                                      forKey:@"finalURLRequest"];
    TNLResponseSource source = [aDecoder decodeIntegerForKey:@"source"];
    NSData *data = [aDecoder decodeObjectOfClass:[NSData class]
                                          forKey:@"data"];

    id<TNLTemporaryFile> temporarySavedFile = nil;
    NSString *temporarySavedFilePath = [aDecoder decodeObjectOfClass:[NSString class]
                                                              forKey:@"temporarySavedFilePath"];
    if (temporarySavedFilePath) {
        temporarySavedFile = [[TNLExpiredTemporaryFile alloc] initWithFilePath:(temporarySavedFilePath.length > 0) ? temporarySavedFilePath : nil];
    }

    return [self initWithFinalURLRequest:URLRequest
                             URLResponse:URLResponse
                                  source:source
                                    data:data
                      temporarySavedFile:temporarySavedFile];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_URLResponse forKey:@"URLResponse"];
    [aCoder encodeObject:_finalURLRequest forKey:@"finalURLRequest"];
    [aCoder encodeInteger:_source forKey:@"source"];
    [aCoder encodeObject:_data forKey:@"data"];

    NSString *temporarySavedFilePath = nil;
    if (_temporarySavedFile) {
        if ([(NSObject *)_temporarySavedFile respondsToSelector:@selector(path)]) {
            temporarySavedFilePath = [(id)_temporarySavedFile path];
        } else {
            temporarySavedFilePath = @"";
        }
    }
    [aCoder encodeObject:temporarySavedFilePath forKey:@"temporarySavedFilePath"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (NSUInteger)hash
{
    return self.URLResponse.hash +
           self.finalURLRequest.hash +
           (NSUInteger)self.source +
           self.data.hash +
           ((self.temporarySavedFile == nil) ? 11 : 3);
}

- (BOOL)isEqual:(id)object
{
    if ([super isEqual:object]) {
        return YES;
    }

    TNLResponseInfo *other = object;
    if (![other isKindOfClass:[TNLResponseInfo class]]) {
        return NO;
    }

    if (self.URLResponse) {
        if (![self.URLResponse tnl_isEqualToResponse:other.URLResponse]) {
            return NO;
        }
    } else if (other.URLResponse) {
        return NO;
    }

    IS_EQUAL_OBJ_PROP_CHECK(self, other, finalURLRequest);

    if (self.source != other.source) {
        return NO;
    }

    if ((self.temporarySavedFile != nil) || (other.temporarySavedFile != nil)) {
        // No 2 temporary saved files are "equal" so if either TNLResponseInfo has a temp file,
        // they are not equal
        return NO;
    }

    IS_EQUAL_OBJ_PROP_CHECK(self, other, data);

    return YES;
}

@end

@implementation TNLResponseInfo (Convenience)

- (TNLHTTPStatusCode)statusCode
{
    return _URLResponse.statusCode;
}

- (NSURL *)finalURL
{
    return _URLResponse.URL ?: _finalURLRequest.URL;
}

- (NSDictionary *)allHTTPHeaderFields
{
    return _URLResponse.allHeaderFields;
}

- (NSString *)valueForResponseHeaderField:(NSString *)headerField
{
    if (!headerField) {
        return nil;
    }

    return _cachedLowercaseHeaderFields[[headerField lowercaseString]];
}

- (nullable NSDictionary<NSString *, NSString *> *)allHTTPHeaderFieldsWithLowerCaseKeys
{
    return _cachedLowercaseHeaderFields;
}

@end

@implementation TNLResponseEncodedRequest
{
    NSURL *_URL;
    TNLHTTPMethod _HTTPMethodValue;
    NSDictionary<NSString *, NSString *> *_allHTTPHeaderFields;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithSourceRequest:(id<TNLRequest>)request
{
    if (self = [super init]) {
        _encodedSourceRequestHadBody = [TNLRequest requestHasBody:request];
        _encodedSourceRequestClassName = [NSStringFromClass([request class]) copy];
        _URL = request.URL;
        _HTTPMethodValue = [TNLRequest HTTPMethodValueForRequest:request];
        _allHTTPHeaderFields = [request respondsToSelector:@selector(allHTTPHeaderFields)] ? [request.allHTTPHeaderFields copy] : nil;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init]) {
        _encodedSourceRequestHadBody = [coder decodeBoolForKey:@"hasBody"];
        _encodedSourceRequestClassName = [coder decodeObjectOfClass:[NSString class] forKey:@"sourceClass"];
        _URL = [coder decodeObjectOfClass:[NSURL class] forKey:@"URL"];
        _HTTPMethodValue = [coder decodeIntegerForKey:@"HTTPMethod"];
        _allHTTPHeaderFields = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"HTTPHeaders"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeBool:_encodedSourceRequestHadBody forKey:@"hasBody"];
    [coder encodeObject:_encodedSourceRequestClassName forKey:@"sourceClass"];
    [coder encodeObject:_URL forKey:@"URL"];
    [coder encodeInteger:_HTTPMethodValue forKey:@"HTTPMethod"];
    [coder encodeObject:_allHTTPHeaderFields forKey:@"HTTPHeaders"];
}

- (nullable NSURL *)URL
{
    return _URL;
}

- (TNLHTTPMethod)HTTPMethodValue
{
    return _HTTPMethodValue;
}

- (nullable NSDictionary<NSString *, NSString *> *)allHTTPHeaderFields
{
    return _allHTTPHeaderFields;
}

- (nullable NSData *)HTTPBody
{
    if (_encodedSourceRequestHadBody) {
        /*
         In order to preserve "isEqual" comparison between the encoded request
         and the source request, we need to have a non-empty body.

         We're arbitrarily using a valid JSON payload as the body, but it could
         really be any payload.
         */
        return [@"{\"body\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return nil;
}

@end

@implementation TNLResponseMetrics
{
    BOOL _final;
    NSArray<TNLAttemptMetrics *> *_attemptMetrics;
}

@synthesize attemptMetrics = _attemptMetrics;

- (instancetype)init
{
    return [self initWithEnqueueDate:[NSDate dateWithTimeIntervalSince1970:0]
                         enqueueTime:0
                        completeDate:nil
                        completeTime:0
                      attemptMetrics:nil];
}

- (instancetype)initWithEnqueueDate:(NSDate *)enqueueDate
                        enqueueTime:(uint64_t)enqueueTime
                       completeDate:(nullable NSDate *)completeDate
                       completeTime:(uint64_t)completeTime
                     attemptMetrics:(nullable NSArray<TNLAttemptMetrics *> *)attemptMetrics
{
    if (self = [super init]) {
        _final = NO;
        _enqueueDate = enqueueDate;
        _enqueueMachTime = enqueueTime;
        _completeDate = completeDate;
        _completeMachTime = completeTime;
        _attemptMetrics = [attemptMetrics mutableCopy] ?: [NSMutableArray array];
        if (gTwitterNetworkLayerAssertEnabled) {
            if (_attemptMetrics.count > 0) {
                TNLAssert([_attemptMetrics[0] attemptType] == TNLAttemptTypeInitial);
            }
        }
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    NSArray<TNLAttemptMetrics *> *attemptMetrics = [aDecoder tnl_decodeArrayOfItemsOfClass:[TNLAttemptMetrics class] forKey:@"attemptMetrics"];
    NSDate *enqueueDate = [aDecoder decodeObjectOfClass:[NSDate class] forKey:@"enqueueDate"] ?: [NSDate dateWithTimeIntervalSince1970:0];
    const uint64_t enqueueTime = (uint64_t)[aDecoder decodeInt64ForKey:@"enqueueTime"];
    const uint64_t completeTime = (uint64_t)[aDecoder decodeInt64ForKey:@"completeTime"];
    NSDate *completeDate = [aDecoder decodeObjectOfClass:[NSDate class] forKey:@"completeDate"];
    if (!completeDate && completeTime) {
        completeDate = [enqueueDate dateByAddingTimeInterval:TNLComputeDuration(enqueueTime, completeTime)];
    }
    return [self initWithEnqueueDate:enqueueDate
                         enqueueTime:enqueueTime
                        completeDate:completeDate
                        completeTime:completeTime
                      attemptMetrics:attemptMetrics];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_attemptMetrics forKey:@"attemptMetrics"];
    [aCoder encodeObject:_enqueueDate forKey:@"enqueueDate"];
    [aCoder encodeInt64:(int64_t)_enqueueMachTime forKey:@"enqueueTime"];
    [aCoder encodeObject:_completeDate forKey:@"completeDate"];
    [aCoder encodeInt64:(int64_t)_completeMachTime forKey:@"completeTime"];
}

- (void)finalizeMetrics
{
    if (_final) {
        return;
    }
    _final = YES;
    _attemptMetrics = [_attemptMetrics copy];
    [_attemptMetrics makeObjectsPerformSelector:@selector(finalizeMetrics)];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (NSUInteger)attemptCount
{
    return _attemptMetrics.count;
}

- (NSUInteger)retryCount
{
    NSUInteger count = 0;
    for (TNLAttemptMetrics *metrics in _attemptMetrics) {
        if (TNLAttemptTypeRetry == metrics.attemptType) {
            count++;
        }
    }
    return count;
}

- (NSUInteger)redirectCount
{
    NSUInteger count = 0;
    for (TNLAttemptMetrics *metrics in _attemptMetrics) {
        if (TNLAttemptTypeRedirect == metrics.attemptType) {
            count++;
        }
    }
    return count;
}

- (void)didEnqueue
{
    if (_final && _enqueueMachTime) {
        return;
    }

    _enqueueMachTime = mach_absolute_time();
    _enqueueDate = [NSDate date];
}

- (nullable NSDate *)firstAttemptStartDate
{
    TNLAttemptMetrics *attemptMetrics = _attemptMetrics.firstObject;
    return attemptMetrics.startDate;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (uint64_t)firstAttemptStartMachTime
#pragma clang diagnostic pop
{
    TNLAttemptMetrics *attemptMetrics = _attemptMetrics.firstObject;
    return attemptMetrics.startMachTime;
}

- (nullable NSDate *)currentAttemptStartDate
{
    TNLAttemptMetrics *attemptMetrics = _attemptMetrics.lastObject;
    return attemptMetrics.startDate;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (uint64_t)currentAttemptStartMachTime
#pragma clang diagnostic pop
{
    TNLAttemptMetrics *attemptMetrics = _attemptMetrics.lastObject;
    return attemptMetrics.startMachTime;
}

- (nullable NSDate *)currentAttemptEndDate
{
    TNLAttemptMetrics *attemptMetrics = _attemptMetrics.lastObject;
    return attemptMetrics.endDate;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (uint64_t)currentAttemptEndMachTime
#pragma clang diagnostic pop
{
    TNLAttemptMetrics *attemptMetrics = _attemptMetrics.lastObject;
    return attemptMetrics.endMachTime;
}

- (void)setCompleteDate:(NSDate *)date machTime:(uint64_t)time
{
    // support providing a complete time if not already set when already final
    if (_final && _completeMachTime) {
        return;
    }
    _completeMachTime = time;
    _completeDate = date;
}

- (void)addInitialStartWithDate:(NSDate *)date machTime:(uint64_t)machTime request:(NSURLRequest *)request
{
    TNLAssert(_attemptMetrics.count == 0);
    _addAttemptStart(self, TNLAttemptTypeInitial, date, machTime, request);
}

- (void)addRetryStartWithDate:(NSDate *)date machTime:(uint64_t)machTime request:(NSURLRequest *)request
{
    _addAttemptStart(self, TNLAttemptTypeRetry, date, machTime, request);
}

- (void)addRedirectStartWithDate:(NSDate *)date machTime:(uint64_t)machTime request:(NSURLRequest *)request
{
    _addAttemptStart(self, TNLAttemptTypeRedirect, date, machTime, request);
}

static void _addAttemptStart(PRIVATE_SELF(TNLResponseMetrics),
                             TNLAttemptType type,
                             NSDate *date,
                             uint64_t machTime,
                             NSURLRequest *request)
{
    if (!self) {
        return;
    }

    if (self->_final) {
        return;
    }

    TNLAssert(request != nil);
    TNLAssert(self->_attemptMetrics != nil);
    TNLAssert(date != nil);
    TNLAttemptMetrics *lastMetrics = self->_attemptMetrics.lastObject;
    if (TNLAttemptTypeInitial == type) {
        TNLAssert(lastMetrics == nil);
    } else {
        TNLAssert(lastMetrics != nil);
        TNLAssert(lastMetrics.endMachTime != 0 && "addEnd:response:operationError: should have been called first!");
        if (!lastMetrics.endMachTime) {
            [lastMetrics setEndDate:date machTime:machTime];
        }
    }

    TNLAttemptMetrics *metrics = [[TNLAttemptMetrics alloc] initWithType:type
                                                               startDate:date
                                                           startMachTime:machTime
                                                                 endDate:nil
                                                             endMachTime:0
                                                                metaData:nil
                                                              URLRequest:request
                                                             URLResponse:nil
                                                          operationError:nil];
    [(NSMutableArray *)self->_attemptMetrics addObject:metrics];
}

- (void)updateCurrentRequest:(NSURLRequest *)request
{
    TNLAttemptMetrics *metrics = _attemptMetrics.lastObject;
    [metrics updateRequest:request];
}

- (void)addEndDate:(NSDate *)date
          machTime:(uint64_t)time
          response:(NSHTTPURLResponse *)response
    operationError:(NSError *)error
{
    TNLAttemptMetrics *lastMetrics = _attemptMetrics.lastObject;
    if (lastMetrics && !lastMetrics.endMachTime) {
        [lastMetrics setEndDate:date machTime:time];
        lastMetrics.URLResponse = response;
        lastMetrics.operationError = error;
    }
}

- (void)addMetaData:(TNLAttemptMetaData *)metaData taskMetrics:(NSURLSessionTaskMetrics *)taskMetrics
{
    TNLAttemptMetrics *lastMetrics = _attemptMetrics.lastObject;
    if (lastMetrics && !lastMetrics.metaData) {
        lastMetrics.metaData = metaData;
    }

    if (taskMetrics) {
        const NSUInteger transactionMetricsCount = taskMetrics.transactionMetrics.count;
        const NSUInteger attemptMetricsCount = self.attemptMetrics.count;

        TNLAttemptType followingType = TNLAttemptTypeRedirect;
        NSUInteger taskMetricsIndex = 0;
        NSUInteger attemptMetricsIndex = 0;
        while (taskMetricsIndex < transactionMetricsCount && attemptMetricsIndex < attemptMetricsCount) {
            NSURLSessionTaskTransactionMetrics *transactionMetrics = taskMetrics.transactionMetrics[transactionMetricsCount - taskMetricsIndex - 1];
            TNLAttemptMetrics *attemptMetrics = self.attemptMetrics[attemptMetricsCount - attemptMetricsIndex - 1];
            const NSURLSessionTaskMetricsResourceFetchType expectedFetchType = attemptMetrics.metaData.localCacheHit ? NSURLSessionTaskMetricsResourceFetchTypeLocalCache : NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad;
            if (expectedFetchType == transactionMetrics.resourceFetchType) {
                if (followingType != TNLAttemptTypeRedirect) {
                    break;
                }
                [attemptMetrics setTaskTransactionMetrics:transactionMetrics];

                followingType = attemptMetrics.attemptType;
                attemptMetricsIndex++;
            }

            taskMetricsIndex++;
        }
    }
}

- (NSString *)description
{
    NSMutableDictionary *topDictionary = [NSMutableDictionary dictionary];
    topDictionary[@"complete"] = (_completeMachTime != 0) ? @"true" : @"false";
    topDictionary[@"duration"] = @(self.totalDuration);
    topDictionary[@"attemptTime"] = @(self.currentAttemptDuration);
    topDictionary[@"queueTime"] = @(self.queuedDuration);
    topDictionary[@"allAttemptsTime"] = @(self.allAttemptsDuration);

    NSMutableArray *attempts = [NSMutableArray arrayWithCapacity:self.attemptMetrics.count];
    for (TNLAttemptMetrics *metrics in self.attemptMetrics) {
        NSMutableDictionary *attemptDict = [NSMutableDictionary dictionary];
        attemptDict[@"duration"] = @(metrics.duration);
        attemptDict[@"type"] = TNLAttemptTypeToString(metrics.attemptType);
        if (metrics.metaData != nil) {
            attemptDict[@"metadata"] = metrics.metaData;
        }
        attemptDict[@"statusCode"] = @(metrics.URLResponse.statusCode);
        if (metrics.URLResponse.URL) {
            attemptDict[@"URL"] = metrics.URLResponse.URL;
        }
        if (metrics.operationError) {
            attemptDict[@"error"] = [NSString stringWithFormat:@"%@.%ld", metrics.operationError.domain, (long)metrics.operationError.code];
        }
#if DEBUG
        if (metrics.taskTransactionMetrics) {
            attemptDict[@"transactionMetrics"] = metrics.taskTransactionMetrics.tnl_dictionaryValue;
        }
#endif
        [attempts addObject:attemptDict];
    }
    if (attempts.count > 0) {
        topDictionary[@"attempts"] = attempts;
    }
    return [NSString stringWithFormat:@"<%@ %p: %@>", NSStringFromClass([self class]), self, topDictionary];
}

- (NSUInteger)hash
{
    if (!_completeMachTime) {
        return NSUIntegerMax;
    }
    return (NSUInteger)(self.totalDuration * 1000ull); // the total duration is a good gauge for hashing
}

- (BOOL)isEqual:(id)object
{
    if ([super isEqual:object]) {
        return YES;
    }

    TNLResponseMetrics *other = object;
    if (![other isKindOfClass:[TNLResponseMetrics class]]) {
        return NO;
    }

    if (self.attemptCount != other.attemptCount) {
        return NO;
    }

    TNLAssert(self.attemptCount == self.attemptMetrics.count);
    TNLAssert(other.attemptCount == other.attemptMetrics.count);

    NSDate *selfStartDate = self.firstAttemptStartDate;
    NSDate *otherStartDate = other.firstAttemptStartDate;
    for (NSUInteger i = 0; i < self.attemptCount; i++) {
        TNLAttemptMetrics *selfAttemptMetrics = self.attemptMetrics[i];
        TNLAttemptMetrics *otherAttemptMetrics = other.attemptMetrics[i];

        if (![selfAttemptMetrics isEqual:otherAttemptMetrics]) {
            return NO;
        }

        if (fabs([selfAttemptMetrics.startDate timeIntervalSinceDate:selfStartDate] - [otherAttemptMetrics.startDate timeIntervalSinceDate:otherStartDate]) > kTNLTimeEpsilon) {
            return NO;
        }
    }

    if (fabs(self.totalDuration - other.totalDuration) > kTNLTimeEpsilon) {
        return NO;
    }

    if (fabs(self.queuedDuration - other.queuedDuration) > kTNLTimeEpsilon) {
        return NO;
    }

    if (fabs(self.allAttemptsDuration - other.allAttemptsDuration) > kTNLTimeEpsilon) {
        return NO;
    }

    if (fabs(self.currentAttemptDuration - other.currentAttemptDuration) > kTNLTimeEpsilon) {
        return NO;
    }

    return YES;
}

- (NSTimeInterval)totalDuration
{
    return [(_completeDate ?: [NSDate date]) timeIntervalSinceDate:_enqueueDate];
}

- (NSTimeInterval)queuedDuration
{
    return [(self.firstAttemptStartDate ?: [NSDate date]) timeIntervalSinceDate:_enqueueDate];
}

- (NSTimeInterval)allAttemptsDuration
{
    return [self.currentAttemptEndDate ?: [NSDate date] timeIntervalSinceDate:self.firstAttemptStartDate ?: [NSDate date]];
}

- (NSTimeInterval)currentAttemptDuration
{
    return [self.currentAttemptEndDate ?: [NSDate date] timeIntervalSinceDate:self.currentAttemptStartDate ?: [NSDate date]];
}

- (TNLResponseMetrics *)deepCopyAndTrimIncompleteAttemptMetrics:(BOOL)trimIncompleteAttemptMetrics
{
    NSMutableArray *dupeSubmetrics = [NSMutableArray arrayWithCapacity:_attemptMetrics.count];
    for (TNLAttemptMetrics *submetric in _attemptMetrics) {
        if (trimIncompleteAttemptMetrics && !submetric.endMachTime) {
            break;
        }
        TNLAttemptMetrics *dupeSubmetric = [submetric copy];
        [dupeSubmetrics addObject:dupeSubmetric];
    }

    TNLResponseMetrics *metrics = [[TNLResponseMetrics alloc] initWithEnqueueDate:self.enqueueDate
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                                                                      enqueueTime:self.enqueueMachTime
#pragma clang diagnostic pop
                                                                     completeDate:self.completeDate
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                                                                     completeTime:self.completeMachTime
#pragma clang diagnostic pop
                                                                   attemptMetrics:dupeSubmetrics];
    return metrics;
}

@end

@implementation TNLResponseMetrics (UnitTesting)

+ (instancetype)fakeMetricsForDuration:(NSTimeInterval)duration
                            URLRequest:(NSURLRequest *)request
                           URLResponse:(nullable NSHTTPURLResponse *)URLResponse
                        operationError:(nullable NSError *)error
{
    uint64_t absoluteDiff = TNLAbsoluteFromTimeInterval(duration);
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:0];
    NSDate *endDate = [startDate dateByAddingTimeInterval:duration];
    TNLResponseMetrics *metrics = [[TNLResponseMetrics alloc] initWithEnqueueDate:startDate
                                                                      enqueueTime:0
                                                                     completeDate:endDate
                                                                     completeTime:absoluteDiff
                                                                   attemptMetrics:nil];
    [metrics addInitialStartWithDate:startDate
                            machTime:0
                             request:request];
    [metrics addEndDate:endDate
               machTime:absoluteDiff
               response:URLResponse
         operationError:error];
    return metrics;
}

@end

@implementation TNLResponseInfo (RetryAfter)

- (BOOL)hasRetryAfterHeader
{
    return self.retryAfterRawValue != nil;
}

- (NSString *)retryAfterRawValue
{
    if (!_rawRetryAfterValue) {
        _rawRetryAfterValue = [self valueForResponseHeaderField:@"Retry-After"] ?: (id)[NSNull null];
    }
    return ([NSNull null] == (id)_rawRetryAfterValue) ? nil : _rawRetryAfterValue;
}

- (NSTimeInterval)retryAfterDelayFromNow
{
    NSDate *retryAfterDate = self.retryAfterDate;
    if (!retryAfterDate) {
        return NSTimeIntervalSince1970;
    }
    return [retryAfterDate timeIntervalSinceDate:[NSDate date]];
}

- (NSDate *)retryAfterDate
{
    if (!_parsedRetryAfterValue) {
        NSString *retryAfterStringValue = self.retryAfterRawValue;
        _parsedRetryAfterValue = [NSHTTPURLResponse tnl_parseRetryAfterValueFromString:retryAfterStringValue];
        if ([_parsedRetryAfterValue isKindOfClass:[NSNumber class]]) {
            _retryAfterDate = [NSDate dateWithTimeIntervalSinceNow:[(NSNumber *)_parsedRetryAfterValue doubleValue]];
        } else if ([_parsedRetryAfterValue isKindOfClass:[NSDate class]]) {
            _retryAfterDate = _parsedRetryAfterValue;
        } else {
            _parsedRetryAfterValue = (id)[NSNull null];
            if (retryAfterStringValue.length > 0) {
                TNLLogError(@"'Retry-After' header of response provided with invalid value: '%@'", retryAfterStringValue);
            }
        }
    }

    TNLAssert(_parsedRetryAfterValue != nil);
    return _retryAfterDate;
}

@end

NSString *TNLAttemptTypeToString(TNLAttemptType type)
{
    switch (type) {
        case TNLAttemptTypeInitial:
            return @"initial";
        case TNLAttemptTypeRedirect:
            return @"redirect";
        case TNLAttemptTypeRetry:
            return @"retry";
    }
    return nil;
}

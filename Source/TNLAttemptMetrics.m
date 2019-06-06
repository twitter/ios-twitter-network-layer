//
//  TNLAttemptMetrics.m
//  TwitterNetworkLayer
//
//  Created on 1/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "NSCoder+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLAttemptMetaData_Project.h"
#import "TNLAttemptMetrics_Project.h"
#import "TNLCommunicationAgent_Project.h"
#import "TNLGlobalConfiguration.h"
#import "TNLTiming.h"

NS_ASSUME_NONNULL_BEGIN

TNLStaticAssert(TNLAttemptCompleteDispositionCount == TNLAttemptTypeCount, ATTEMPT_TYPE_COUNT_DOESNT_MATCH_ATTEMPT_COMPLETE_DISPOSITION_COUNT);

@implementation TNLAttemptMetrics
{
    BOOL _final;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    [self doesNotRecognizeSelector:_cmd];
    abort();
}

- (instancetype)initWithType:(TNLAttemptType)type
                   startDate:(NSDate *)startDate
               startMachTime:(uint64_t)startMachTime
                     endDate:(nullable NSDate *)endDate
                 endMachTime:(uint64_t)endMachTime
                    metaData:(nullable TNLAttemptMetaData *)metaData
                  URLRequest:(NSURLRequest *)request URLResponse:(nullable NSHTTPURLResponse *)response
              operationError:(nullable NSError *)error
{
   int64_t attemptId = 0;
   arc4random_buf(&attemptId, sizeof(int64_t));

    return [self initWithAttemptId:attemptId
                              type:type
                         startDate:startDate
                     startMachTime:startMachTime
                           endDate:endDate
                       endMachTime:endMachTime
                          metaData:metaData
                        URLRequest:request
                       URLResponse:response
                    operationError:error];
}

- (instancetype)initWithAttemptId:(int64_t)attemptId
                             type:(TNLAttemptType)type
                        startDate:(NSDate *)startDate
                    startMachTime:(uint64_t)startMachTime
                          endDate:(nullable NSDate *)endDate
                      endMachTime:(uint64_t)endMachTime
                         metaData:(nullable TNLAttemptMetaData *)metaData
                       URLRequest:(NSURLRequest *)request
                      URLResponse:(nullable NSHTTPURLResponse *)response
                   operationError:(nullable NSError *)error
{
    if (self = [super init]) {
#if !TARGET_OS_WATCH
        _reachabilityStatus = TNLNetworkReachabilityUndetermined;
        _captivePortalStatus = TNLCaptivePortalStatusUndetermined;
#endif
        _attemptId = attemptId;
        _attemptType = type;
        _startDate = startDate;
        _startMachTime = startMachTime;
        _endDate = endDate;
        _endMachTime = endMachTime;
        _metaData = metaData;
        _URLRequest = [request copy];
        _URLResponse = response;
        _operationError = error;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    const int64_t attemptId = [aDecoder decodeInt64ForKey:@"attemptId"];
    const TNLAttemptType type = [aDecoder decodeIntegerForKey:@"attemptType"];
    NSDate *startDate = [aDecoder decodeObjectOfClass:[NSDate class] forKey:@"startDate"] ?: [NSDate dateWithTimeIntervalSince1970:0];
    const uint64_t startMachTime = (uint64_t)[aDecoder decodeInt64ForKey:@"startMachTime"];
    NSDate *endDate = [aDecoder decodeObjectOfClass:[NSDate class] forKey:@"endDate"];
    const uint64_t endMachTime = (uint64_t)[aDecoder decodeInt64ForKey:@"endMachTime"];
    TNLAttemptMetaData *metaData = [aDecoder decodeObjectOfClass:[TNLAttemptMetaData class] forKey:@"metaData"];
    NSURLRequest *request = [aDecoder decodeObjectOfClass:[NSURLRequest class] forKey:@"URLRequest"];
    NSHTTPURLResponse *response = [aDecoder decodeObjectOfClass:[NSHTTPURLResponse class] forKey:@"URLResponse"];
    NSError *error = [aDecoder decodeObjectOfClass:[NSError class] forKey:@"operationError"];

    self = [self initWithAttemptId:attemptId
                              type:type
                         startDate:startDate
                     startMachTime:startMachTime
                           endDate:endDate
                       endMachTime:endMachTime
                          metaData:metaData
                        URLRequest:request
                       URLResponse:response
                    operationError:error];
    if (self) {
        _final = YES;

        _APIErrors = [[aDecoder tnl_decodeArrayOfItemsOfClass:[NSError class] forKey:@"APIErrors"] copy];
        _responseBodyParseError = [aDecoder decodeObjectOfClass:[NSError class] forKey:@"parseError"];

#if !TARGET_OS_WATCH
        NSNumber *number;
        number = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:@"reachabilityStatus"];
        _reachabilityStatus = (number) ? [number integerValue] : TNLNetworkReachabilityUndetermined;

        number = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:@"reachabilityFlags"];
        _reachabilityFlags = [number unsignedIntValue];

        number = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:@"captivePortalStatus"];
        _captivePortalStatus = (number) ? [number integerValue] : TNLCaptivePortalStatusUndetermined;

        _WWANRadioAccessTechnology = [aDecoder decodeObjectOfClass:[NSString class] forKey:@"WWANRadioAccessTechnology"];

#endif

#if TARGET_OS_IOS && !TARGET_OS_UIKITFORMAC
        _carrierInfo = TNLCarrierInfoFromDictionary([aDecoder decodeObjectOfClass:[NSDictionary class]
                                                                           forKey:@"carrierInfo"]);
#endif
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeInt64:_attemptId forKey:@"attemptId"];
    [aCoder encodeInteger:_attemptType forKey:@"attemptType"];
    [aCoder encodeObject:_startDate forKey:@"startDate"];
    [aCoder encodeInt64:(int64_t)_startMachTime forKey:@"startMachTime"];
    [aCoder encodeObject:_endDate forKey:@"endDate"];
    [aCoder encodeInt64:(int64_t)_endMachTime forKey:@"endMachTime"];
    [aCoder encodeObject:_metaData forKey:@"metaData"];
    [aCoder encodeObject:_URLRequest forKey:@"URLRequest"];
    [aCoder encodeObject:_URLResponse forKey:@"URLResponse"];

    [aCoder encodeObject:TNLErrorToSecureCodingError(_operationError) forKey:@"operationError"];
    [aCoder encodeObject:TNLErrorToSecureCodingError(_responseBodyParseError) forKey:@"parseError"];
    NSMutableArray<NSError *> *apiErrors = (_APIErrors) ? [[NSMutableArray alloc] initWithCapacity:_APIErrors.count] : nil;
    for (NSError *apiError in _APIErrors) {
        [apiErrors addObject:TNLErrorToSecureCodingError(apiError)];
    }
    [aCoder encodeObject:[apiErrors copy] forKey:@"APIErrors"];

#if !TARGET_OS_WATCH
    [aCoder encodeObject:@(_reachabilityStatus) forKey:@"reachabilityStatus"];
    [aCoder encodeObject:@(_reachabilityFlags) forKey:@"reachabilityFlags"];
    [aCoder encodeObject:@(_captivePortalStatus) forKey:@"captivePortalStatus"];
    [aCoder encodeObject:_WWANRadioAccessTechnology forKey:@"WWANRadioAccessTechnology"];
#endif

#if TARGET_OS_IOS && !TARGET_OS_UIKITFORMAC
    [aCoder encodeObject:TNLCarrierInfoToDictionary(_carrierInfo) forKey:@"carrierInfo"];
#endif
}

- (void)finalizeMetrics
{
    if (_final) {
        return;
    }
    _final = YES;
    [_metaData finalizeMetaData];
}

#if !TARGET_OS_WATCH
- (void)setCommunicationMetricsWithAgent:(nullable TNLCommunicationAgent *)agent
{
    if (!agent) {
        return;
    }

    if (_reachabilityStatus != TNLNetworkReachabilityUndetermined) {
        return;
    }

    _reachabilityStatus = agent.currentReachabilityStatus;
    _reachabilityFlags = agent.currentReachabilityFlags;
    _WWANRadioAccessTechnology = [agent.currentWWANRadioAccessTechnology copy];
    _carrierInfo = agent.currentCarrierInfo;
    _captivePortalStatus = agent.currentCaptivePortalStatus;
}
#endif

- (NSString *)description
{
    NSMutableString *string = [NSMutableString string];
    [string appendFormat:@"<%@ %p: type=%@, duration=%.2fs", NSStringFromClass([self class]), self, TNLAttemptTypeToString(self.attemptType), self.duration];
    if (self.URLResponse) {
        [string appendFormat:@", HTTP=%ld", (long)self.URLResponse.statusCode];
    }
    if (self.operationError) {
        [string appendFormat:@", error=%@.%ld", self.operationError.domain, (long)self.operationError.code];
    }
    if (self.metaData) {
        [string appendFormat:@", metaData.class=%@", NSStringFromClass([self.metaData class])];
    }
    [string appendString:@">"];
    return string;
}

- (NSTimeInterval)duration
{
    const NSTimeInterval duration = [(_endDate ?: [NSDate date]) timeIntervalSinceDate:_startDate];

    TNLAssertMessage(duration >= 0, @"-[%@ %@] is negative! %f", NSStringFromClass([self class]), NSStringFromSelector(_cmd), duration);
    return duration;
}

- (NSUInteger)hash
{
    return (NSUInteger)_startDate.hash;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }

    TNLAttemptMetrics *other = object;
    if (![other isKindOfClass:[TNLAttemptMetrics class]]) {
        return NO;
    }

    if (self.attemptType != other.attemptType) {
        return NO;
    }

    if (fabs(self.duration - other.duration) > kTNLTimeEpsilon) {
        return NO;
    }

    if (self.metaData != other.metaData) {
        if (![self.metaData isEqual:other.metaData]) {
            return NO;
        }
    }

    if (!TNLSecureCodingErrorsAreEqual(self.operationError, other.operationError)) {
        return NO;
    }

    if (self.URLResponse != other.URLResponse) {
        if (self.URLResponse.statusCode != other.URLResponse.statusCode) {
            return NO;
        }
        if (![self.URLResponse.URL isEqual:other.URLResponse.URL]) {
            return NO;
        }
    }

    if (self.URLRequest != other.URLRequest) {
        if (![self.URLRequest isEqual:other.URLRequest]) {
            return NO;
        }
    }

#if !TARGET_OS_WATCH
    if (self.reachabilityFlags != other.reachabilityFlags) {
        return NO;
    }

    if (self.reachabilityStatus != other.reachabilityStatus) {
        return NO;
    }

    if (self.WWANRadioAccessTechnology != other.WWANRadioAccessTechnology) {
        if (![self.WWANRadioAccessTechnology isEqualToString:other.WWANRadioAccessTechnology]) {
            return NO;
        }
    }
#endif // !WATCH

    if (self.APIErrors != other.APIErrors) {
        if (self.APIErrors.count != other.APIErrors.count) {
            return NO;
        }
        // just compare error codes and domains
        for (NSUInteger i = 0; i < self.APIErrors.count; i++) {
            if (!TNLSecureCodingErrorsAreEqual(self.APIErrors[i], other.APIErrors[i])) {
                return NO;
            }
        }
    }

    if (!TNLSecureCodingErrorsAreEqual(self.responseBodyParseError, other.responseBodyParseError)) {
        return NO;
    }

#if !TARGET_OS_WATCH
    id<TNLCarrierInfo> carrierInfo = self.carrierInfo;
    id<TNLCarrierInfo> otherCarrierInfo = other.carrierInfo;
    if (carrierInfo != otherCarrierInfo) {
        if (!carrierInfo || !otherCarrierInfo) {
            return NO;
        }
        if (carrierInfo.allowsVOIP != otherCarrierInfo.allowsVOIP) {
            return NO;
        }
        if (carrierInfo.mobileCountryCode != otherCarrierInfo.mobileCountryCode) {
            if (![carrierInfo.mobileCountryCode isEqualToString:otherCarrierInfo.mobileCountryCode]) {
                return NO;
            }
        }
        if (carrierInfo.mobileNetworkCode != otherCarrierInfo.mobileNetworkCode) {
            if (![carrierInfo.mobileNetworkCode isEqualToString:otherCarrierInfo.mobileNetworkCode]) {
                return NO;
            }
        }
        if (carrierInfo.isoCountryCode != otherCarrierInfo.isoCountryCode) {
            if (![carrierInfo.isoCountryCode isEqualToString:otherCarrierInfo.isoCountryCode]) {
                return NO;
            }
        }
    }
#endif // !WATCH

    return YES;
}

- (void)setMetaData:(nullable TNLAttemptMetaData *)metaData
{
    if (_final && _metaData) {
        return;
    }
    _metaData = metaData;
}

- (void)setEndDate:(nonnull NSDate *)endDate machTime:(uint64_t)time
{
    if (_final && _endMachTime) {
        return;
    }
    _endMachTime = time;
    _endDate = endDate;
#if !TARGET_OS_WATCH
    [self setCommunicationMetricsWithAgent:[TNLGlobalConfiguration sharedInstance].metricProvidingCommunicationAgent];
#endif
}

- (void)setOperationError:(nullable NSError *)error
{
    if (_final && _operationError) {
        return;
    }
    _operationError = error;
}

- (void)setURLResponse:(nullable NSHTTPURLResponse *)response
{
    if (_final && _URLResponse) {
        return;
    }
    _URLResponse = response;
}

- (void)setTaskTransactionMetrics:(nullable NSURLSessionTaskTransactionMetrics *)metrics
{
    if (_final && _taskTransactionMetrics) {
        return;
    }
    _taskTransactionMetrics = metrics;
}

- (void)setResponseBodyParseError:(nullable NSError *)responseBodyParseError
{
    if (_final) {
        return;
    }
    _responseBodyParseError = responseBodyParseError;
}

- (void)setAPIErrors:(nullable NSArray<NSError *> *)APIErrors
{
    if (_final) {
        return;
    }
    TNLAssert(0 == APIErrors.count || [APIErrors[0] isKindOfClass:[NSError class]]);
    _APIErrors = [APIErrors copy];
}

- (void)updateRequest:(NSURLRequest *)request
{
    if (_final) {
        return;
    }
    TNLAssert(request);
    TNLAssert([_URLRequest.URL isEqual:request.URL]);
    _URLRequest = [request copy];
}

#pragma mark NSCopying

- (id)copyWithZone:(nullable NSZone *)zone
{
    TNLAttemptMetaData *metaData = _metaData ? [[TNLAttemptMetaData allocWithZone:zone] initWithMetaDataDictionary:_metaData.metaDataDictionary] : nil;
    TNLAttemptMetrics *dupeSubmetric = [[TNLAttemptMetrics allocWithZone:zone] initWithAttemptId:_attemptId
                                                                                            type:_attemptType
                                                                                       startDate:_startDate
                                                                                   startMachTime:_startMachTime
                                                                                         endDate:_endDate
                                                                                     endMachTime:_endMachTime
                                                                                        metaData:metaData
                                                                                      URLRequest:_URLRequest
                                                                                     URLResponse:_URLResponse
                                                                                  operationError:_operationError];
    dupeSubmetric->_taskTransactionMetrics = _taskTransactionMetrics;
    dupeSubmetric->_APIErrors = _APIErrors;
    dupeSubmetric->_responseBodyParseError = _responseBodyParseError;
#if !TARGET_OS_WATCH
    dupeSubmetric->_reachabilityStatus = _reachabilityStatus;
    dupeSubmetric->_reachabilityFlags = _reachabilityFlags;
    dupeSubmetric->_WWANRadioAccessTechnology = [_WWANRadioAccessTechnology copyWithZone:zone];
    dupeSubmetric->_carrierInfo = _carrierInfo;
    dupeSubmetric->_captivePortalStatus = _captivePortalStatus;
#endif
    dupeSubmetric->_final = NO;
    return dupeSubmetric;
}

@end

NS_ASSUME_NONNULL_END

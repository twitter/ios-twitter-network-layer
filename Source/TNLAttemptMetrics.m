//
//  TNLAttemptMetrics.m
//  TwitterNetworkLayer
//
//  Created on 1/15/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

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
               startMachTime:(uint64_t)startMachTime
                 endMachTime:(uint64_t)endMachTime
                    metaData:(nullable TNLAttemptMetaData *)metaData
                  URLRequest:(NSURLRequest *)request URLResponse:(nullable NSHTTPURLResponse *)response
              operationError:(nullable NSError *)error
{
   int64_t attemptId = 0;
   arc4random_buf(&attemptId, sizeof(int64_t));

    return [self initWithAttemptId:attemptId
                              type:type
                     startMachTime:startMachTime
                       endMachTime:endMachTime
                          metaData:metaData
                        URLRequest:request
                       URLResponse:response
                    operationError:error];
}

- (instancetype)initWithAttemptId:(int64_t)attemptId
                             type:(TNLAttemptType)type
                    startMachTime:(uint64_t)startMachTime
                      endMachTime:(uint64_t)endMachTime
                         metaData:(nullable TNLAttemptMetaData *)metaData
                       URLRequest:(NSURLRequest *)request
                      URLResponse:(nullable NSHTTPURLResponse *)response
                   operationError:(nullable NSError *)error
{
    if (self = [super init]) {
#if !TARGET_OS_WATCH
        _reachabilityStatus = TNLNetworkReachabilityUndetermined;
#endif
        _attemptId = attemptId;
        _attemptType = type;
        _startMachTime = startMachTime;
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
    int64_t attemptId = [aDecoder decodeInt64ForKey:@"attemptId"];
    TNLAttemptType type = [aDecoder decodeIntegerForKey:@"attemptType"];
    uint64_t startMachTime = (uint64_t)[aDecoder decodeInt64ForKey:@"startMachTime"];
    uint64_t endMachTime = (uint64_t)[aDecoder decodeInt64ForKey:@"endMachTime"];
    TNLAttemptMetaData *metaData = [aDecoder decodeObjectOfClass:[TNLAttemptMetaData class] forKey:@"metaData"];
    NSURLRequest *request = [aDecoder decodeObjectOfClass:[NSURLRequest class] forKey:@"URLRequest"];
    NSHTTPURLResponse *response = [aDecoder decodeObjectOfClass:[NSHTTPURLResponse class] forKey:@"URLResponse"];
    NSError *error = [aDecoder decodeObjectOfClass:[NSError class] forKey:@"operationError"];

    self = [self initWithAttemptId:attemptId
                              type:type
                     startMachTime:startMachTime
                       endMachTime:endMachTime
                          metaData:metaData
                        URLRequest:request
                       URLResponse:response
                    operationError:error];
    if (self) {
        _final = YES;

        _APIErrors = [[aDecoder decodeObjectOfClass:[NSArray class]
                                             forKey:@"APIErrors"] copy];
        _responseBodyParseError = [aDecoder decodeObjectOfClass:[NSError class]
                                                         forKey:@"parseError"];

#if !TARGET_OS_WATCH
        _reachabilityStatus = [(NSNumber *)[aDecoder decodeObjectOfClass:[NSNumber class]
                                                                  forKey:@"reachabilityStatus"] integerValue];
        _reachabilityFlags = [(NSNumber *)[aDecoder decodeObjectOfClass:[NSNumber class]
                                                                 forKey:@"reachabilityFlags"] unsignedIntValue];
        _WWANRadioAccessTechnology = [aDecoder decodeObjectOfClass:[NSString class]
                                                            forKey:@"WWANRadioAccessTechnology"];
#endif
#if TARGET_OS_IOS
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
    [aCoder encodeInt64:(int64_t)_startMachTime forKey:@"startMachTime"];
    [aCoder encodeInt64:(int64_t)_endMachTime forKey:@"endMachTime"];
    [aCoder encodeObject:_metaData forKey:@"metaData"];
    [aCoder encodeObject:_URLRequest forKey:@"URLRequest"];
    [aCoder encodeObject:_URLResponse forKey:@"URLResponse"];
    [aCoder encodeObject:_operationError forKey:@"error"]; // FIXME:[nobrien] - the userInfo could have content that is not encodable
    [aCoder encodeObject:_APIErrors forKey:@"APIErrors"];
    [aCoder encodeObject:_responseBodyParseError forKey:@"parseError"];

#if !TARGET_OS_WATCH
    [aCoder encodeObject:@(_reachabilityStatus) forKey:@"reachabilityStatus"];
    [aCoder encodeObject:@(_reachabilityFlags) forKey:@"reachabilityFlags"];
    [aCoder encodeObject:_WWANRadioAccessTechnology forKey:@"WWANRadioAccessTechnology"];
#endif
#if TARGET_OS_IOS
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
    return TNLComputeDuration(_startMachTime, _endMachTime);
}

- (NSUInteger)hash
{
    return (NSUInteger)_startMachTime;
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

    if (self.operationError != other.operationError) {
        if (![self.operationError isEqual:other.operationError]) {
            return NO;
        }
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
        if (![self.APIErrors isEqualToArray:other.APIErrors]) {
            return NO;
        }
    }

    if (self.responseBodyParseError != other.responseBodyParseError) {
        if (![self.responseBodyParseError isEqual:other.responseBodyParseError]) {
            return NO;
        }
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

- (void)setEndMachTime:(uint64_t)time
{
    if (_final && _endMachTime) {
        return;
    }
    _endMachTime = time;
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
                                                                                   startMachTime:_startMachTime
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
#endif
    dupeSubmetric->_final = NO;
    return dupeSubmetric;
}

@end

NS_ASSUME_NONNULL_END

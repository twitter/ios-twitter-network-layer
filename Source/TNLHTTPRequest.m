//
//  TNLHTTPRequest.m
//  TwitterNetworkLayer
//
//  Created on 2/28/15.
//  Copyright (c) 2015 Twitter. All rights reserved.
//

#import "NSDictionary+TNLAdditions.h"
#import "TNL_Project.h"
#import "TNLError.h"
#import "TNLHTTPRequest.h"
#import "TNLRequestConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - TNLHTTPRequest

@implementation TNLHTTPRequest
{
@protected
    NSURL *_URL;
    TNLHTTPMethod _HTTPMethodValue;
    NSDictionary *_allHTTPHeaderFields;
    NSData *_HTTPBody;
    NSInputStream *_HTTPBodyStream;
    NSString *_HTTPBodyFilePath;
}

@synthesize URL = _URL;
@synthesize HTTPMethodValue = _HTTPMethodValue;
@synthesize allHTTPHeaderFields = _allHTTPHeaderFields;
@synthesize HTTPBody = _HTTPBody;
@synthesize HTTPBodyStream = _HTTPBodyStream;
@synthesize HTTPBodyFilePath = _HTTPBodyFilePath;

#pragma mark init

- (instancetype)init
{
    return [self initWithURL:nil];
}

- (instancetype)initWithURL:(nullable NSURL *)url
{
    return [self initWithURLRequest:(url) ? [[NSURLRequest alloc] initWithURL:url] : nil];
}

- (instancetype)initWithURLRequest:(nullable NSURLRequest *)request
{
    return [self initWithURLRequest:request HTTPBodyFilePath:nil];
}

- (instancetype)initWithURLRequest:(nullable NSURLRequest *)request
                  HTTPBodyFilePath:(nullable NSString *)bodyFilePath
{
    NSString *const HTTPMethod = request.HTTPMethod;
    return [self initWithURL:request.URL
             HTTPMethodValue:(HTTPMethod) ? TNLHTTPMethodFromString(HTTPMethod) : TNLHTTPMethodGET
            HTTPHeaderFields:request.allHTTPHeaderFields
                    HTTPBody:request.HTTPBody
              HTTPBodyStream:request.HTTPBodyStream
            HTTPBodyFilePath:bodyFilePath];
}

- (instancetype)initWithURL:(nullable NSURL *)url
            HTTPMethodValue:(TNLHTTPMethod)method
           HTTPHeaderFields:(nullable NSDictionary *)fields
                   HTTPBody:(nullable NSData *)body
             HTTPBodyStream:(nullable NSInputStream *)bodyStream
           HTTPBodyFilePath:(nullable NSString *)bodyFilePath
{
    if (self = [super init]) {
        _URL = url;
        _HTTPMethodValue = method;
        _allHTTPHeaderFields = [fields copy];
        _HTTPBody = body; // to avoid the cost of memcpy for large bodies, we'll put the responsibility on the caller to not modify the body
        _HTTPBodyStream = bodyStream;
        _HTTPBodyFilePath = [bodyFilePath copy];
    }
    return self;
}

#pragma mark NSSecureCoding

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    NSURL *URL = [aDecoder decodeObjectOfClass:[NSURL class]
                                        forKey:@"URL"];
    TNLHTTPMethod HTTPMethodValue = [aDecoder decodeIntegerForKey:@"HTTPMethodValue"];
    NSDictionary *allHTTPHeaderFields = [[aDecoder decodeObjectOfClass:[NSDictionary class]
                                                                forKey:@"allHTTPHeaderFields"] copy];
    NSData *HTTPBody = [aDecoder decodeObjectOfClass:[NSData class]
                                              forKey:@"HTTPBody"];
    NSString *HTTPBodyFilePath = [aDecoder decodeObjectOfClass:[NSString class]
                                                        forKey:@"HTTPBodyFilePath"];

    return [self initWithURL:URL
             HTTPMethodValue:HTTPMethodValue
            HTTPHeaderFields:allHTTPHeaderFields
                    HTTPBody:HTTPBody
              HTTPBodyStream:nil
            HTTPBodyFilePath:HTTPBodyFilePath];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_URL forKey:@"URL"];
    [aCoder encodeInteger:_HTTPMethodValue forKey:@"HTTPMethodValue"];
    [aCoder encodeObject:_allHTTPHeaderFields forKey:@"allHTTPHeaderFields"];
    [aCoder encodeObject:_HTTPBody forKey:@"HTTPBody"];
    [aCoder encodeObject:_HTTPBodyFilePath forKey:@"HTTPBodyFilePath"];
    if (_HTTPBodyStream) {
        TNLAssert(NO && "HTTPBodyStream cannot be encoded!");
//        @throw [NSException exceptionWithName:NSInvalidArchiveOperationException reason:[NSString stringWithFormat:@"Cannot encode a %@ with HTTPBodyStream set to anything other than nil!", NSStringFromClass([self class])] userInfo:nil];
    }
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

#pragma mark Convenience Constructors

+ (instancetype)HTTPRequestWithRequest:(nullable id<TNLRequest>)request
{
    return [[self alloc] initWithURL:[request respondsToSelector:@selector(URL)] ? request.URL : nil
                     HTTPMethodValue:[TNLRequest HTTPMethodValueForRequest:request]
                    HTTPHeaderFields:[request respondsToSelector:@selector(allHTTPHeaderFields)] ? request.allHTTPHeaderFields : nil
                            HTTPBody:[request respondsToSelector:@selector(HTTPBody)] ? request.HTTPBody : nil
                      HTTPBodyStream:[request respondsToSelector:@selector(HTTPBodyStream)] ? request.HTTPBodyStream : nil
                    HTTPBodyFilePath:[request respondsToSelector:@selector(HTTPBodyFilePath)] ? request.HTTPBodyFilePath : nil];
}

+ (instancetype)POSTRequestWithURL:(nullable NSURL *)url
                  HTTPHeaderFields:(nullable NSDictionary *)fields
                          HTTPBody:(nullable NSData *)body
{
    return [[self alloc] initWithURL:url
                     HTTPMethodValue:TNLHTTPMethodPOST
                    HTTPHeaderFields:fields
                            HTTPBody:body
                      HTTPBodyStream:nil
                    HTTPBodyFilePath:nil];
}

+ (instancetype)POSTRequestWithURL:(nullable NSURL *)url
                  HTTPHeaderFields:(nullable NSDictionary *)fields
                    HTTPBodyStream:(nullable NSInputStream *)bodyStream
{
    return [[self alloc] initWithURL:url
                     HTTPMethodValue:TNLHTTPMethodPOST
                    HTTPHeaderFields:fields
                            HTTPBody:nil
                      HTTPBodyStream:bodyStream
                    HTTPBodyFilePath:nil];
}

+ (instancetype)POSTRequestWithURL:(nullable NSURL *)url
                  HTTPHeaderFields:(nullable NSDictionary *)fields
                  HTTPBodyFilePath:(nullable NSString *)bodyFilePath
{
    return [[self alloc] initWithURL:url
                     HTTPMethodValue:TNLHTTPMethodPOST
                    HTTPHeaderFields:fields
                            HTTPBody:nil
                      HTTPBodyStream:nil
                    HTTPBodyFilePath:bodyFilePath];
}

+ (instancetype)GETRequestWithURL:(nullable NSURL *)url
                 HTTPHeaderFields:(nullable NSDictionary *)fields
{
    return [[self alloc] initWithURL:url
                     HTTPMethodValue:TNLHTTPMethodGET
                    HTTPHeaderFields:fields
                            HTTPBody:nil
                      HTTPBodyStream:nil
                    HTTPBodyFilePath:nil];
}

+ (instancetype)PUTRequestWithURL:(nullable NSURL *)url
                 HTTPHeaderFields:(nullable NSDictionary *)fields
{
    return [[self alloc] initWithURL:url
                     HTTPMethodValue:TNLHTTPMethodPUT
                    HTTPHeaderFields:fields
                            HTTPBody:nil
                      HTTPBodyStream:nil
                    HTTPBodyFilePath:nil];
}

+ (instancetype)DELETERequestWithURL:(nullable NSURL *)url
                    HTTPHeaderFields:(nullable NSDictionary *)fields
{
    return [[self alloc] initWithURL:url
                     HTTPMethodValue:TNLHTTPMethodDELETE
                    HTTPHeaderFields:fields
                            HTTPBody:nil
                      HTTPBodyStream:nil
                    HTTPBodyFilePath:nil];
}

+ (instancetype)HEADRequestWithURL:(nullable NSURL *)url
                  HTTPHeaderFields:(nullable NSDictionary *)fields
{
    return [[self alloc] initWithURL:url
                     HTTPMethodValue:TNLHTTPMethodHEAD
                    HTTPHeaderFields:fields
                            HTTPBody:nil
                      HTTPBodyStream:nil
                    HTTPBodyFilePath:nil];
}

#pragma mark Properties

- (nullable NSURL *)URL
{
    return _URL;
}

- (TNLHTTPMethod)HTTPMethodValue
{
    return _HTTPMethodValue;
}

- (nullable NSDictionary *)allHTTPHeaderFields
{
    return _allHTTPHeaderFields;
}

- (nullable NSString *)valueForHTTPHeaderField:(NSString *)field
{
    NSDictionary *fields = self.allHTTPHeaderFields;
    return [fields tnl_objectsForCaseInsensitiveKey:field].firstObject;
}

- (nullable NSData *)HTTPBody
{
    return _HTTPBody;
}

- (nullable NSInputStream *)HTTPBodyStream
{
    return _HTTPBodyStream;
}

- (nullable NSString *)HTTPBodyFilePath
{
    return _HTTPBodyFilePath;
}

#pragma mark NSMutableCopying

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    TNLMutableHTTPRequest *copy = [[TNLMutableHTTPRequest allocWithZone:zone] initWithURL:self.URL
                                                                          HTTPMethodValue:self.HTTPMethodValue
                                                                         HTTPHeaderFields:_allHTTPHeaderFields
                                                                                 HTTPBody:self.HTTPBody
                                                                           HTTPBodyStream:self.HTTPBodyStream
                                                                         HTTPBodyFilePath:self.HTTPBodyFilePath];
    return copy;
}

#pragma mark isEqual + hash

- (NSUInteger)hash
{
    NSUInteger hash = self.HTTPBody.hash +
                        self.URL.hash +
                        (NSUInteger)self.HTTPMethodValue +
                        self.HTTPBodyFilePath.hash +
                        self.HTTPBodyStream.hash +
                        self.allHTTPHeaderFields.count; // use the count of headers, not the hash since the dictionary will be case incensitive in comparison
    return hash;
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[TNLHTTPRequest class]]) {
        return [TNLRequest isRequest:self equalTo:object];
    }

    return [super isEqual:object];
}

@end

#pragma mark - TNLMutableHTTPRequest

@implementation TNLMutableHTTPRequest

@dynamic URL;
@dynamic HTTPMethodValue;
@dynamic allHTTPHeaderFields;
@dynamic HTTPBody;
@dynamic HTTPBodyStream;
@dynamic HTTPBodyFilePath;

- (void)setURL:(nullable NSURL *)URL
PROP_RETAIN_ASSIGN_IMP(URL);

- (void)setHTTPMethodValue:(TNLHTTPMethod)HTTPMethodValue
PROP_RETAIN_ASSIGN_IMP(HTTPMethodValue);

- (void)setHTTPBody:(nullable NSData *)HTTPBody
PROP_RETAIN_ASSIGN_IMP(HTTPBody);

- (void)setHTTPBodyStream:(nullable NSInputStream *)HTTPBodyStream
PROP_RETAIN_ASSIGN_IMP(HTTPBodyStream);

- (void)setHTTPBodyFilePath:(nullable NSString *)HTTPBodyFilePath
PROP_COPY_IMP(HTTPBodyFilePath);

- (void)setAllHTTPHeaderFields:(nullable NSDictionary *)allHTTPHeaderFields
{
    if (_allHTTPHeaderFields != allHTTPHeaderFields) {
        _allHTTPHeaderFields = [allHTTPHeaderFields mutableCopy];
    }
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field
{
    [(NSMutableDictionary *)_allHTTPHeaderFields tnl_setObject:value
                                         forCaseInsensitiveKey:field];
}

- (void)removeAllValuesForHTTPHeaderField:(NSString *)field
{
    [(NSMutableDictionary *)_allHTTPHeaderFields tnl_removeObjectsForCaseInsensitiveKey:field];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TNLHTTPRequest *copy = [[TNLHTTPRequest allocWithZone:zone] initWithURL:self.URL
                                                            HTTPMethodValue:self.HTTPMethodValue
                                                           HTTPHeaderFields:_allHTTPHeaderFields
                                                                   HTTPBody:self.HTTPBody
                                                             HTTPBodyStream:self.HTTPBodyStream
                                                           HTTPBodyFilePath:self.HTTPBodyFilePath];
    return copy;
}

- (instancetype)initWithURL:(nullable NSURL *)url
            HTTPMethodValue:(TNLHTTPMethod)method
           HTTPHeaderFields:(nullable NSDictionary *)fields
                   HTTPBody:(nullable NSData *)body
             HTTPBodyStream:(nullable NSInputStream *)bodyStream
           HTTPBodyFilePath:(nullable NSString *)bodyFilePath
{
    self = [super initWithURL:url
              HTTPMethodValue:method
             HTTPHeaderFields:fields
                     HTTPBody:body
               HTTPBodyStream:bodyStream
             HTTPBodyFilePath:bodyFilePath];
    if (self) {
        _allHTTPHeaderFields = [NSMutableDictionary dictionaryWithDictionary:_allHTTPHeaderFields];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END

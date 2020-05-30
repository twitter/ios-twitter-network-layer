//
//  TAPISearchRequests.m
//  TNLExample
//
//  Created on 5/24/18.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TAPIError.h"
#import "TAPISearchRequests.h"

@implementation TAPISearchRequest
{
    NSString *_query;
    TNLParameterCollection *_nextResultsParams;
}

- (instancetype)initWithQuery:(NSString *)query
{
    if (self = [super init]) {
        _query = [query copy];
    }
    return self;
}

- (instancetype)initWithNextResultsObject:(id)nextResultsObject
{
    TNLParameterCollection *params = nextResultsObject;
    if (![params isKindOfClass:[TNLParameterCollection class]]) {
        return nil;
    }

    if (self = [super init]) {
        _nextResultsParams = [params copy];
    }
    return self;
}

- (NSString *)endpoint
{
    return @"search/tweets.json";
}

- (void)prepareParameters:(TNLMutableParameterCollection *)params
{
    [super prepareParameters:params];
    if (_query) {
        params[@"q"] = _query;
        params[@"count"] = @100;
        params[@"include_entities"] = @1;
    } else if (_nextResultsParams) {
        [params addParametersFromParameterCollection:_nextResultsParams];
    } else {
        assert(false);
    }
}

+ (Class)responseClass
{
    return [TAPISearchResponse class];
}

@end

@implementation TAPISearchResponse

- (void)prepare
{
    [super prepare];
    if (!self.anyError) {
        NSDictionary *root = _parsedObject;
        if ([root isKindOfClass:[NSDictionary class]]) {
            _statuses = [TAPIStatusModelsFromJSONObjects(root[@"statuses"]) copy];
            if (_statuses.count) {
                NSDictionary *metaData = root[@"search_metadata"];
                if ([metaData isKindOfClass:[NSDictionary class]]) {
                    NSString *nextResults = metaData[@"next_results"];
                    if ([nextResults hasPrefix:@"?"]) {
                        nextResults = [nextResults substringFromIndex:1];
                    }
                    if (nextResults.length) {
                        TNLParameterCollection *params = [[TNLParameterCollection alloc] initWithURLEncodedString:nextResults options:0];
                        if (params.count) {
                            _nextResultsObject = params;
                        }
                    }
                }
            }
        }
        if (_statuses.count == 0) {
            _parseError = [NSError errorWithDomain:TAPIParseErrorDomain
                                              code:TAPIParseErrorCodeUnexpectedResponseStructure
                                          userInfo:nil];
        }
    }
}

- (NSArray<id<TAPIImageEntityModel>> *)imagesFromStatuesRemovingSensitiveImages:(BOOL)removeSensitive
{
    NSMutableArray *results = [[NSMutableArray alloc] init];
    for (id<TAPIStatusModel> status in self.statuses) {
        if (!status.possiblySensitive || !removeSensitive) {
            for (id<TAPIImageEntityModel> image in status.images) {
                [results addObject:image];
            }
        }
    }
    return [results copy];
}

@end

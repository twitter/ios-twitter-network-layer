//
//  TNLRequest.h
//  TwitterNetworkLayer
//
//  Created on 5/23/14.
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//

#import <TwitterNetworkLayer/TNLHTTP.h>

NS_ASSUME_NONNULL_BEGIN

@class TNLRequestOperation;
@class TNLRequestConfiguration;

// TODO:[nobrien] - support creating a TNLRequest with resume data
// see NSURLSessionDownloadTaskResumeData

#pragma twitter startignorestylecheck

/**
 TNLRequest protocol

 The core encapsulation of the properties required to populate the content of a network request.

 The lifecycle of a `TNLRequestOperation`'s network request progresses in a structured way:

 1. The operation is created with an original network request object that conforms to `TNLRequest` (can be a `TNLHTTPRequest`, an `NSURLRequest` or some custom implementation of `TNLRequest`)
   - See `[TNLRequestOperation originalRequest]` and `[TNLResponse originalRequest]`
 2. The original request is hydrated:
   - if there is a `TNLRequestHydrater`, that will be used for hydrating the request
   - if there is no `TNLRequestHydrater`, the original request will be used
   - See `[TNLRequestOperation hydratedRequest]`
 3. The hydrated request is verified with `[TNLRequest validateRequest:againstConfiguration:error:]`
 4. The hydrated request is converted to an `NSURLRequest` for transmission (under the hood)
   - See `[TNLRequestOperation hydratedURLRequest]`
 5. The operation executes upon the request

 __See Also:__ `TNLRequest(Utilities)`, `TNLRequestHydrater`, `TNLHTTPRequest` and `NSURLRequest`

 ## Example 1: NSURLRequest as a TNLRequest

 One could simply use an NSURLRequest as the original request and optionally hydrate it.

     // Optionally implement `TNLRequestHydrater`
     - (void)tnl_requestOperation:(TNLRequestOperation *)op
                   hydrateRequest:(NSURLRequest *)request
                       completion:(TNLRequestHydrateCompletionBlock)complete
     {
         NSMutableURLRequest *mRequest = [request mutableCopy];
         [mRequest setValue:[@(time()) stringValue] forHTTPHeaderField:@"x-timestamp"];
         [self internal_signMutableRequest:mRequest];
         complete(mRequest, nil);
     }

     // Make operation
     - (void)executeRequest
     {
         NSString *URLString = [NSString stringWithFormat:@"https://api.someplace.com/upload/%@", self.userID];
         NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
         request.HTTPMethod = @"POST";
         request.URL = [NSURL URLWithString:URLString];
         request.HTTPBody = [NSJSONSerializer dataWithJSONObject:@{ @"id" : self.userID,
                                                                    @"message" : self.message }
                                                         options:0
                                                           error:NULL];
         [request setValue:TNLHTTPContentTypeJSON forHTTPHeaderField:@"content-type"];
         TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                               configuration:nil
                                                                    delegate:self];
         [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
     }

 ## Example 2: TNLHTTPRequest as a TNLRequest

 One could also use a `TNLHTTPRequest` as the original request and optionally hydrate it.
 The benefit with `TNLHTTPRequest` over `NSURLRequest` are:
   1. the HTTP body can be a file (see `[TNLHTTPRequest HTTPBodyFilePath]`)
   2. it doesn't have the superfluous configuration methods that NSURLRequest has.

     // Optionally implement `TNLRequestHydrater`
     - (void)tnl_requestOperation:(TNLRequestOperation *)op
                   hydrateRequest:(TNLHTTPRequest *)request
                       completion:(TNLRequestHydrateCompletionBlock)complete
     {
         TNLMutableHTTPRequest *mRequest = [request mutableCopy];
         [mRequest setValue:[@(time()) stringValue] forHTTPHeaderField:@"x-timestamp"];
         [self internal_signMutableRequest:mRequest];
         complete(mRequest, nil);
     }

     // Make operation
     - (void)executeRequest
     {
         NSString *URLString = [NSString stringWithFormat:@"https://api.someplace.com/upload/%@", self.userID];
         NSURL *URL = [NSURL URLWithString:URLString];
         NSData *body = [NSJSONSerializer dataWithJSONObject:@{ @"id" : self.userID,
                                                                @"message" : self.message }
                                                     options:0
                                                       error:NULL];
         NSDictionary *headers = @{ @"content-type" : TNLHTTPContentTypeJSON };
         TNLHTTPRequest *request = [TNLHTTPRequest POSTRequestWithURL:URL
                                                     HTTPHeaderFields:headers
                                                             HTTPBody:body];
         TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                               configuration:nil
                                                                    delegate:self];
         [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
     }

 ## Example 3: Custom Request Object

 Given that the point of a request is to encapsulate the information relevant to the consumer,
 it shouldn't have any ties to __HTTP__ as a protocol.  So, another way to use `TNLRequest` is to
 encapsulate the necessary info of a request in an object and hydrate that with a `TNLRequestHydrater`.

     // Custom Request Object
     @interface CustomPostMessageRequest : NSObject <TNLRequest>
     @property (nonatomic, copy) NSString *userID;
     @property (nonatomic, copy) NSString *message;
     @end

     // Hydration
     - (void)tnl_requestOperation:(TNLRequestOperation *)op
                   hydrateRequest:(CustomPostMessageRequest *)request
                       completion:(TNLRequestHydrateCompletionBlock)complete
     {
         NSString *URLString = [NSString stringWithFormat:@"https://api.someplace.com/upload/%@", self.userID];
         NSURL *URL = [NSURL URLWithString:URLString];
         NSData *body = [NSJSONSerializer dataWithJSONObject:@{ @"id" : request.userID,
                                                                @"message" : request.message }
                                                     options:0
                                                       error:NULL];
         NSDictionary *headers = @{ @"content-type" : TNLHTTPContentTypeJSON };
         TNLMutableHTTPRequest *mRequest = [TNLHTTPRequest POSTRequestWithURL:URL
                                                             HTTPHeaderFields:headers
                                                                     HTTPBody:body];
         [self internal_signMutableRequest:mRequest];
         complete(mRequest, nil);
     }

     // Making the Call
     - (void)executeRequest
     {
         CustomPostMessageRequest *request = [[CustomPostMessageRequest alloc] init];
         request.userID = self.account.userID;
         request.message = self.textInputField.text;
         TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                               configuration:nil
                                                                    delegate:self];
         [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
     }

 ## Example 4: Even Better Custom Request Objects

 Taking the benefits from Example #3, we can naturally extend the pattern into a hierarchy of requests that use polymorphic inheritance to customize a specific requests behavior.  This makes scaling requests over a large API much simpler with greater code reuse.

    // Public Interfaces

    @interface CustomBaseRequest : NSObject <TNLRequest>
    @end

    @interface CustomPostMessageRequest : CustomBaseRequest
    @property (nonatomic, copy) NSString *userID;
    @property (nonatomic, copy) NSString *message;
    @end

    // Private Interfaces

    @interface CustomBaseRequest (HTTP)
    // Override for customization
    - (BOOL)useTLS;
    - (NSString *)host;
    - (NSString *)endpoint;
    - (TNLParameterCollection *)parameters; // HTTP body on POST, URL query otherwise
    @end

    @implementation CustomBaseRequest

    - (BOOL)useTLS
    {
        return YES;
    }

    - (NSString *)host
    {
        return @"api.someplace.com";
    }

    - (NSString *)endpoint
    {
        return nil;
    }

    - (TNLParameterCollection *)parameters
    {
        return nil;
    }

    - (NSURL *)URL
    {
        NSString *URLStr = [NSString stringWithFormat:@"%@://%@",
                                                      self.useTLS ? @"https" : @"http",
                                                      self.host];
        if (self.endpoint) {
            URLStr = [NSString stringWithFormat:@"%@%@%@",
                                                URLStr,
                                                [self.endpoint hasPrefix:@"/"] ? @"" : @"/",
                                                self.endpoint];
        }
        if (TNLHTTPMethodValuePOST != [TNLRequest HTTPMethodValueForRequest:self]) {
            TNLParameterCollection *params = self.parameters;
            if (params.count > 0) {
                 URLStr = [URLStr stringByAppendingFormat:@"?%@",
                            [params URLEncodedStringValueWithOptions:TNLURLEncodingOptionStableOrder]];
            }
        }
        return [NSURL URLWithString:URLStr];
    }

    - (NSData *)HTTPBody
    {
        if (TNLHTTPMethodValuePOST != [TNLRequest HTTPMethodValueForRequest:self]) {
            return nil;
        }

        NSData *json;
        TNLParameterCollection *params = self.parameters;
        if (params.count > 0) {
            json = [NSJSONSerialization dataWithJSONObject:params.dictionaryValue
                                                   options:0
                                                     error:NULL];
        }
        return json;
    }

    - (NSDictionary *)allHTTPHeaderFields
    {
        NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
        if (TNLHTTPMethodValuePOST == [TNLRequest HTTPMethodValueForRequest:self]) {
             headers[@"content-type"] = TNLHTTPContentTypeJSON;
        }
        headers[@"timestamp"] = [NSString stringWithFormat:@"%ll", time()];
        return headers;
    }

    @end

    @implementation CustomPostMessageRequest

    - (NSString *)endpoint
    {
        return [NSString stringWithFormat:@"post/%@", self.userID"];
    }

    - (TNLParameterCollection *)parameters
    {
        TNLMutableParameterCollection *params = [super.parameters mutableCopy] ?: [[TNLMutableParameterCollection alloc] init];
        params[@"message"] = self.message;
        return params;
    }

    - (NSDictionary *)allHTTPHeaderFields
    {
       NSMutableDictionary *headers = [super.allHTTPHeaderFields mutableCopy] ?: [[NSMutableDictionary alloc] init];
       headers[@"rand"] = [@(rand()) stringValue];
       return headers;
    }

    - (TNLHTTPMethodValue)HTTPMethodValue
    {
        return TNLHTTPMethodValuePOST;
    }

    @end

    // Making the call (same as Example #3)
    - (void)executeRequest
    {
        CustomPostMessageRequest *request = [[CustomPostMessageRequest alloc] init];
        request.userID = self.account.userID;
        request.message = self.textInputField.text;
        TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                              configuration:nil
                                                                   delegate:self];
        [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequestOperation:op];
    }

    // Hydration
    - (void)tnl_requestOperation:(TNLRequestOperation *)op
                  hydrateRequest:(CustomBaseRequest *)request
                      completion:(TNLRequestHydrateCompletionBlock)complete
    {
        NSError *error;
        NSMutableURLRequest *mRequest = [TNLHTTPRequest mutableURLRequestWithRequest:request
                                                                               error:&error];
        if (mRequest) {
            [self internal_signMutableURLRequest:mRequest];
        }
        complete(mRequest, error);
    }

 You can see that the boiler plate is encapsulated with the base request object while the subclassed
 request does very minimal configuration to turn its public properties (the ones that the consumer
 will interact with) into a well formed HTTP request.  The execution code is just as simple as
 example #3, and the hydration work is so minimal that it doesn't have to couple the request's
 conversion to being a well formed HTTP request in the hydrater, leaving the hydrater free to focus
 on its use case (like request signing).  With each added request adopting the pattern, the value
 becomes evident.

 @note These examples are illistrutive of how one would construct a request using `TNLRequest` and
 are not robust in implementation.  Any production app should implement the necessary code safety.

 @discussion ...

 ## @protocol TNLRequest
 */
@protocol TNLRequest <NSObject>

#pragma mark Comparison
@optional

/**
 Method for checking equality between two objects conforming to `TNLRequest` (optional)

 When checking `TNLRequest` equivalency, if neither object implements `isEqualToRequest:`,
 `[TNLRequest isRequest:equalTo:]` is preferred
 @param request The other request to compare with
 @return `YES` if equal, else `NO`
 */
- (BOOL)isEqualToRequest:(nullable id<TNLRequest>)request;

#pragma mark Required HTTP Protocol Methods
@required

/**
 The `NSURL` of the request (required)

 @return an `NSURL`
 */
- (nullable NSURL *)URL;

#pragma mark Optional HTTP Protocol Methods
@optional

/**
 The HTTP Method of the request (optional)

 Implement either `HTTPMethod`, `HTTPMethodValue` or neither (which defaults to `@"GET"`).
 If both `HTTPMethod` and `HTTPMethodValue` are provided, `HTTPMethod` is preferred and
 `HTTPMethodValue` will be ignored.
 @return An `NSString` of the HTTP Method (ex: `@"GET"`)
 @discussion __See Also:__ `HTTPMethodValue`
 */
- (nullable NSString *)HTTPMethod;

/**
 The HTTP Method of the request (optional), see `TNLHTTPMethod`

 Implement either `HTTPMethod`, `HTTPMethodValue` or neither (which defaults to `@"GET"`).
 If both `HTTPMethod` and `HTTPMethodValue` are provided, `HTTPMethod` is preferred and
 `HTTPMethodValue` will be ignored.
 @return A `TNLHTTPMethod` enum value of the HTTP Method (ex: `TNLHTTPMethodGET`)
 @discussion __See Also:__ `HTTPMethod`
 */
- (TNLHTTPMethod)HTTPMethodValue;

/**
 The additional HTTP Header fields for the request (optional)

 @return An `NSDictionary` of HTTP Header fields
 @note HTTP Header fields are case insensitive so it is wise to prevent ambiguous header fields with
 multiple entries of different case.  See `NSDictionary(TNLAdditions)` for useful methods.
 @discussion __See Also:__ `NSDictionary(TNLAdditions)` and `NSMutableDictionary(TNLAdditions)`
 */
- (nullable NSDictionary<NSString *, NSString *> *)allHTTPHeaderFields;

/**
 The data for the HTTP body of an HTTP POST network request (optional)

 Implement either `HTTPBody`, `HTTPBodyFilePath` or `HTTPBodyStream`.
 If more than one is implemented, the priority is `HTTPBody`, `HTTPBodyFilePath` then `HTTPBodyStream`.
 @return an `NSData` of the HTTP body
 @note Supported with `TNLRequestExecutionModeBackground` upload operations.
 */
- (nullable NSData *)HTTPBody;

/**
 The file path for the HTTP body of an HTTP POST network request (optional).
 Useful for background upload requests.

 Implement either `HTTPBody`, `HTTPBodyFilePath` or `HTTPBodyStream`.
 If more than one is implemented, the priority is `HTTPBody`, `HTTPBodyFilePath` then `HTTPBodyStream`.
 @return an `NSString` of the path to a file for use as the HTTP body
 @note Supported with `TNLRequestExecutionModeBackground` upload operations.
 */
- (nullable NSString *)HTTPBodyFilePath;

/**
 The input stream for the HTTP body of an HTTP POST network request (optional)

 Implement either `HTTPBody`, `HTTPBodyFilePath` or `HTTPBodyStream`.
 If more than one is implemented, the priority is `HTTPBody`, `HTTPBodyFilePath` then `HTTPBodyStream`.
 @return an `NSInputStream` for providing the HTTP body
 @note `HTTPBodyStream` requires the server to support HTTP Header field `@"Transfer-Encoding"` of
 `@"Chunked"` and the `@"Content-Length"` HTTP Header field will not be provided (even if manually
 set in the `allHTTPHeaderFields`).  This is defined behavior by __Apple__.
 When in doubt, use the `HTTPBodyFilePath` instead.
 @note Cannot be used for a `TNLRequestExecutionModeBackground` upload operation, use `HTTPBodyFilePath` or `HTTPBody`
 */
- (nullable NSInputStream *)HTTPBodyStream;

@end

#pragma twitter stopignorestylecheck

/**
 `NSURLRequest` implicitly conforms to `TNLRequest`.  This category makes that conformance explicit.

     @interface NSURLRequest (TNLExtensions) <<TNLRequest>>
     @end

 @note `NSURLRequest` has numerous _configuration_ properties which are replaced by the
 `NSURLSessionConfiguration` in the `NSURLSession` stack.
 As such, they are ignored in the __TNL__ stack.
 Use `TNLRequestConfiguration` instead.
 */
@interface NSURLRequest (TNLExtensions) <TNLRequest>
@end

NS_ASSUME_NONNULL_END
// Import the header necessary to make class methods on the TNLRequest protocol "possible"
// It's a fake out, but works well for code completion and as a mental model for utility methods
// on a protocol vs using having the same utilities live on a tangential class or be global functions.
#import <TwitterNetworkLayer/TNLRequest+Utilities.h>
NS_ASSUME_NONNULL_BEGIN

/**
 # TNLRequest (Utilities)

 Utilities for `TNLRequest` protocol (not restricted to `TNLHTTPRequest` concrete class)
 */
@interface TNLRequest (Utilities)

/**
 Convenience validation method for requests

 @param request The request to validate
 @param config  The configuration to validate against
 @param error   If validation fails, `NO` will be returned and _error_ will be populated (if provided)

 @return `YES` if valid, `NO` if invalid and _error_ (if provided) will be populated.
*/
+ (BOOL)validateRequest:(nullable id<TNLRequest>)request
   againstConfiguration:(nullable TNLRequestConfiguration *)config
                  error:(out NSError * __nullable * __nullable)error;

/** Convenience method for making a hydrated request from a simple requests */

/**
 Convenience method for making an `NSURLRequest` from a `TNLRequest`.
 Useful for request hydration, see `TNLRequestHydrater`.

 @param request The request to convert
 @param config  The (optional) configuration to apply the `NSURLRequest` (applies what is possible)
 @param error   If an `NSURLRequest` cannot be created from the provided _request_,
 `NO` will be returned and _error_ will be populated (if provided)

 @return The new `NSURLRequest` or `nil`.  If `nil`, then _error_ (if provided) will be populated.
 */
+ (nullable NSURLRequest *)URLRequestForRequest:(nullable id<TNLRequest>)request
                                  configuration:(nullable TNLRequestConfiguration *)config
                                          error:(out NSError * __nullable * __nullable)error;

/** See `URLRequestForRequest:configuration:error:` */
+ (nullable NSURLRequest *)URLRequestForRequest:(nullable id<TNLRequest>)request
                                          error:(out NSError * __nullable * __nullable)error;

/**
 Convenience method for making an `NSMutableURLRequest` from a `TNLRequest`.
 Useful for request hydration, see `TNLRequestHydrater`.

 @param request The request to convert
 @param config  The (optional) configuration to apply the `NSURLRequest` (applies what is possible)
 @param error   If an `NSMutableURLRequest` cannot be created from the provided _request_,
 `NO` will be returned and _error_ will be populated (if provided)

 @return The new `NSMutableURLRequest` or `nil`.  If `nil`, then _error_ (if provided) will be populated.
 */
+ (nullable NSMutableURLRequest *)mutableURLRequestForRequest:(nullable id<TNLRequest>)request
                                                configuration:(nullable TNLRequestConfiguration *)config
                                                        error:(out NSError * __nullable * __nullable)error;

/** See `mutableURLRequestForRequest:configuration:error:` */
+ (nullable NSMutableURLRequest *)mutableURLRequestForRequest:(nullable id<TNLRequest>)request
                                                        error:(out NSError * __nullable * __nullable)error;

/**
 Convenience method for extracting the `TNLHTTPMethod` from a `TNLRequest`

 @param request The request from which to extract the `TNLHTTPMethod` from

 @return The `TNLHTTPMethod` of the _request_.  Default if undefined is `TNLHTTPMethodGET`.
 */
+ (TNLHTTPMethod)HTTPMethodValueForRequest:(nullable id<TNLRequest>)request;

/**
 Convenience method for extracting the `NSString` HTTP Method from a `TNLRequest`

 @param request The request from which to extract the HTTP Method from

 @return The `NSString` HTTP Method of the _request_.  Default if undefined is `@"GET"`.
 */
+ (NSString *)HTTPMethodForRequest:(nullable id<TNLRequest>)request;

/**
 Convenience method to check if a given `TNLRequest` has an HTTP Body
 */
+ (BOOL)requestHasBody:(nullable id<TNLRequest>)request;

/**
 Convenience method for comparing two `TNLRequest` conforming objects that doesn't use the
 `[TNLRequest isEqualToRequest:]` method

 @param request1 The first request
 @param request2 The second request

 @return `YES` if equal, `NO` otherwise.
 */
+ (BOOL)isRequest:(nullable id<TNLRequest>)request1
          equalTo:(nullable id<TNLRequest>)request2;

/**
 Like `[TNLRequest isRequest:equalTo:]` method, but with a faster HTTP Body check.
 Instead of checking the full bytes of the body, just check if there body exists or not.

 @param request1 The first request
 @param request2 The second request
 @param quickBodyCheck Pass `YES` to just validate that both requests either had a body or both did not have a body

 @return `YES` if equal, `NO` otherwise.
 */
  + (BOOL)isRequest:(nullable id<TNLRequest>)request1
            equalTo:(nullable id<TNLRequest>)request2
quickBodyComparison:(BOOL)quickBodyCheck;

@end

NS_ASSUME_NONNULL_END

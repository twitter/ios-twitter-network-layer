# Twitter Network Layer (a.k.a TNL)

The __Twitter Network Layer__ (__TNL__) is a framework for interfacing with the __Apple__ provided
`NSURLSession` stack that provides additional levels of control and insight over networking requests,
provides simple configurability and minimizes the cognitive load necessary to maintain a robust and
wide-reaching networking system.

## OSI Layering with TNL

The __Twitter Network Layer__ sits on top of the _connection/session layer_ provided by the
__Apple NSURL__ framework.  Those frameworks are build on top of the __HTTP/1.1__ and __HTTP/2__.
The layer chart appears like this:

```
/--------------------------------------\
|                                      |
|              User Layer              |
|       The actual user (Layer 8)      |
|                                      |
|--------------------------------------|
|                                      |
|          Application Layer           |
|       MVC, MVVM, etc (Layer 7e)      |
|                                      |
|--------------------------------------|
|                                      |
|     Concrete Operation/App Layer     |  <------ Operations, Requests &
|             TNL (Layer 7d)           |          Responses built on TNL
|                                      |
|--------------------------------------|
|                                      |
|     Abstract Operation/App Layer     |
|             TNL (Layer 7c)           |  <------ TNL
|                                      |
|--------------------------------------|
|                                      |
|         Connection/App Layer         |
|        NSURL Stack (Layer 7b)        |
|                                      |
|--------------------------------------|
|                                      |
|          Protocol/App Layer          |
|     HTTP/1.1 & HTTP/2 (Layer 7a)     |
|                                      |
|--------------------------------------|
|                                      |
|            Presentation Layer        |
| Encryption & Serialization (Layer 6) |
|                                      |
|--------------------------------------|
|                                      |
|            Session Layer             |
|      A Feature of TCP (Layer 5)      |
|                                      |
|--------------------------------------|
|                                      |
|            Transport Layer           |
|             TCP (Layer 4)            |
|                                      |
|--------------------------------------|
|                                      |
|         Routing/Network Layer        |
|              IP (Layer 3)            |
|                                      |
|--------------------------------------|
|                                      |
|            Data Link Layer           |
|          IEEE 802.X (Layer 2)        |
|                                      |
|--------------------------------------|
|                                      |
|            Physical Layer            |
|          Ethernet (Layer 1)          |
|                                      |
\--------------------------------------/
```

## Brief Overview

### Features

__Twitter Network Layer__ provides a framework on top of __Apple__'s `NSURLSession` framework with
numerous benefits.  Here are some of the features provided by __TNL__:

- All the features of `NSURLSession`, simplified where appropriate
- `NSOperation` based request operations (for `NSOperation` features)
- Strong separation of roles in the framework's objects
- Immutable/mutable pairings of requests (`TNLHTTPRequest`) and configurations (`TNLRequestConfiguration`)
- Encapsulated immutable responses (`TNLResponse`)
- Prioritization of requests
- Selectable response body consumption modes (`NSData` storage, callback chunking or saving to file)
- Request hydration (enables polymorphic requests and dynamically populated requests)
- Dynamic retrying with retry policies
- More events (request operation state transitions, progress, network state/condition updates, etc)
- Modular delegates for separation of roles and increased reusability and easy overriding

### Usage

The high level concept of how to use __TNL__ is rather straightforward:

1. Set up any reuseable settings (by doing any combination of the following):
    - Build shared accessors to resuable `TNLRequestConfiguration` instances
    - Implement a `TNLRequestDelegate` (if added functionality is desired beyond just handling the result)
    - Configure a `TNLRequestConfiguration` for reuse
    - Configure the `TNLGlobalConfiguration`
2. Set up any reusable `TNLRequestOperationQueue` objects once (ex: one for API requests, one for image requests, etc.)
    - `[TNLRequestOperationQueue initWithIdentifier:]`
3. Generate and enqueue any desired `TNLRequestOperation` with the following objects:
    - `TNLRequest` conforming object (including `TNLHTTPRequest` concrete class and `NSURLRequest`)
    - `TNLRequestConfiguration` (optional)
    - `TNLRequestDelegate` (optional)
4. Handle the events appropriately via the callbacks, particularly the completion callback that provides the `TNLResponse`
    - Delegate callbacks will go to the appropriate sub-protocol in the `TNLRequestOperation`'s `TNLRequestDelegate`

# HOWTO

## Where To Start

 __Twitter Network Layer__ documentation starts with this `README.md` and progresses through the APIs via their documentation.

## Overview of a Network Operation

### Core Objects

 The core objects of a service based architecture are _request_, _response_ and _operation/task/action_ (referred to as an _operation_ from here on).
 The _request_ encapsulates data to send and is not actionable;
 the _response_ encapsulates the data received and is not actionable;
 and the _operation_ is the object that delivers the _request_ and retrieves the _response_ and
 is the only actionable object in the set of core objects.

 This high level concept translates directly into a network architecture as we will have _requests_
 that encapsulate the data of an _HTTP request_ which are _Headers_ and a _Body_, _responses_ that
 encapsulate the data of an _HTTP response_ which are _Headers_ and a _Body_, and last the _operation_
 that executes delivering the _request_ and retrieving the _response_.

### Core Object Breakdown

 - _request_
   - encapsulates data to send
   - immutability provides stability
   - not actionable, just data
   - `TNLRequest` is the protocol for requests in __TNL__
   - `TNLHTTPRequest` and `NSURLRequest` are concrete classes (both are immutable/mutable pairs)
 - _response_
   - encapsulates data received
   - immutability provides stability
   - not actionable, just data
   - `TNLResponse` is the object for responses in __TNL__ (composite object that includes an `NSHTTPURLResponse`)
 - _operation_
   - the executing object
   - delivers the _request_
   - retrieves the _response_
   - actionable (e.g. starting, canceling, priotiziation, modifying dependencies)
   - `TNLRequestOperation` is the operation in __TNL__ (subclasses `NSOperation`) and is backed by `NSURLSessionTask`

### Support Objects

 In addition to a service architecture having _requests_, _operations_ and _responses_;
 support objects are often present that aid in the management of the executing _operations_,
 configuration of their behavior and delegation of decisions or events.

 The _configuration_ object encapsulates __how__ an _operation_ behaves.  It will have no impact on
 what is sent in the _operation_ (that's the _request_), but can modify how it is sent.
 For instance, the _configuration_ can indicate a maximum duration that the _operation_ can take
 before it should fail.

 The _delegate_ object provides the extensibility of on demand decision making when prudent as well
 as the delivery of events as the _operation_ executes.

 The _manager_ object coordinates the execution of multiple _operations_ within a logical grouping.


### Support Object Breakdown

 - _configuration_
   - encapsulation of behavior settings
   - `TNLRequestConfiguration` is the config in __TNL__ (applied per _operation_)
   - `NSURLSessionConfiguration` is the config in __NSURL__ stack (applied per _manager_)
 - _delegate_
   - provides extensibility
   - has callbacks for on demand decisions
   - has callbacks for events as they occur
   - `TNLRequestDelegate` is the delegate in __TNL__ (provided per _operation_)
   - `NSURLSessionDelegate` is the delegate in __NSURL__ stack (provided per _manager_)
 - _manager_
   - coordinator of multiple _operations_
   - permits grouping of _operations_
   - `TNLRequestOperationQueue` is the manager object in __TNL__
   - `NSURLSession` is the manager object in __NSURL__ stack

 Note: You can already see there is a fundamental architecture difference between `NSURLSession` networking
 and __Twitter Network Layer__.  The _configuration_ and _delegate_ per _operation_ approach in __TNL__
 is much more scalable when dealing with dozens or hundreds of unique configurations and/or delegates
 given a plethora of requests and their needs.  Coupling the _configuration_ and/or _delegate_ to the
 reusable _manager_ object(s) is unwieldy and can lead to mistakes w.r.t. correct configuration and event
 on a per request basis.

## Building a Request

 __TNL__ uses the `TNLRequest` as the interface for all network requests.  In practice, the protocol
 is used in one of 3 ways:

 1. Concrete `TNLHTTPRequest`
   - Configuring a concrete `TNLHTTPRequest` object (or `TNLMutableHTTPRequest`)
 2. `NSURLRequest`
   - `NSURLRequest` explicitely conforms to `TNLRequest` protocol via a category in __TNL__ making it supported as _request_ object.
   - However, since __TNL__ rigidly segregates _configuration_ from _request_, only the _request_ properties on `NSURLRequest` are observed and the _configuration_ properties of `NSURLRequest` are ignored.
 3. Implementing a custom `TNLRequest`
   - __TNL__ supports having anything that conforms to `TNLRequest` as an _original request_ for an _operation_.
   - Makes it simple for an object that encapsulates the minimal amount of information necessary to take the place as the _original request_.
     - You could have a `APPRetrieveBlobRequest` that has 1 property, the identifier for the "Blob" call _blobIdentifier_.
     - That object doesn't need to have any methods that actually represent anything related to an _HTTP request_ and that's ok.  However, in order for the _operation_ to send the _original request_, it needs to be able to be treated as an __HTTP request__, which is to say it must conform to `TNLRequest`.  This can be done in 2 ways:
       1. have the object implement `TNLRequest` and have its methods that populate the values by the relevant properties (in our example, the blob identifier)
       2. have the _delegate_ implement the _request hydration_ callback to convert the opaque request into a well formed `TNLRequest` ready for __HTTP__ transport.
     - See _Custom TNLRequest_ examples

 When it comes to making the choice, it can boil down to convenience vs simplicity of reuse.
 If you have a one shot request that has no reuse, options __1__ and __2__ will suffice.
 If you have a request that can be reused throughout the code base, option __3__ clearly offers the cleanest interface.
 By having the caller only need to know the class of the request and the relevant values for populating the request,
 any concern over the _HTTP_ structure is completely eliminated.

### Concrete TNLRequest with TNLHTTPRequest

 __TNLHTTPRequest:__

```
NSString *URLString = [NSString stringWithFormat:@"http://api.myapp.com/blob/%tu", blobIdentifier];
NSURL *URL = [NSURL URLWithString:URLString];
TNLHTTPRequest *request = [TNLHTTPRequest GETRequestWithURL:URL
                                           HTTPHeaderFields:@{@"User-Agent": [MYAPPDELEGATE userAgentString]}];
```

 __TNLMutableHTTPRequest:__

```
NSString *URLString = [NSString stringWithFormat:@"http://api.myapp.com/blob/%tu", blobIdentifier];
NSURL *URL = [NSURL URLWithString:URLString];
TNLMutableHTTPRequest *mRequest = [[TNLMutableHTTPRequest alloc] init];
mRequest.HTTPMethodValue = TNLHTTPMethodValueGET;
mRequest.URL = URL;
[mRequest setValue:[MYAPPDELEGATE userAgentString] forHTTPHeaderField:@"User-Agent"];
```

### NSURLRequest

```
NSString *URLString = [NSString stringWithFormat:@"http://api.myapp.com/blob/%tu", blobIdentifier];
NSURL *URL = [NSURL URLWithString:URLString];
NSMutableURLRequest *mRequest = [[NSMutableURLRequest alloc] init];
mRequest.HTTPMethod = @"GET";
mRequest.URL = URL;
[mRequest setValue:[MYAPPDELEGATE userAgentString] forHTTPHeaderField:@"User-Agent"];
```

### Custom TNLRequest

 __1) Request Hydration__

```
APPRetrieveBlobRequest *request = [[APPRetrieveBlobRequest alloc] initWithBlobIdentifier:blobIdentifier];

// ... elsewhere ...

- (void)tnl_requestOperation:(TNLRequestOperation *)op
              hydrateRequest:(APPRetrieveBlobRequest *)request // we know the type
                  completion:(TNLRequestHydrateCompletionBlock)complete
{
     NSString *URLString = [NSString stringWithFormat:@"http://api.myapp.com/blob/%tu", blobRequest.blobIdentifier];
     NSURL *URL = [NSURL URLWithString:URLString];
     TNLHTTPRequest *newReq = [TNLHTTPRequest GETRequestWithURL:URL
                                               HTTPHeaderFields:@{@"User-Agent": [MYAPPDELEGATE userAgentString]}];
     complete(newReq);
}
```

 __2) Request with HTTP support__

```
APPRetrieveBlobRequest *request = [[APPRetrieveBlobRequest alloc] initWithBlobIdentifier:blobIdentifier];

// ... elsewhere ...

@implementation APPRetrieveBlobRequest

- (NSURL *)URL
{
    NSString *URLString = [NSString stringWithFormat:@"http://api.myapp.com/blob/%tu", self.blobIdentifier];
    return [NSURL URLWithString:URLString];
}

- (NSDictionary *)allHTTPHeaderFields
{
    return @{@"User-Agent":[MYAPPDELEGATE userAgentString]};
}

// POINT OF IMPROVEMENT:
// utilize polymorphism and have an APPBaseRequest class that implements
// the "allHTTPHeaderFields" so that all subclasses (including APPRetrieveBlobRequest)
// will inherit the desired defaults.
// This can apply to a wide range of HTTP related TNLHTTPRequest properties
// or even composition of subcomponents that are aggregated to a single property.
// For example: the host of the URL (api.myapp.com) could be provided
// as a property on APPBaseRequest that permits subclasses to override the host, and then
// the construction of the `URL` uses composition of variation properites that the subclasses
// can provide.

@end
```

## Inspecting a Response

 When an _operation_ completes, a _TNLResponse_ is populated and provided to the completion block
 or completion callback (depending on if you use a _delegate_ or not).  The _TNLResponse_ has all
 the information necessary to understand how the _operation_ completed, as well as what information
 was retrieve.  Additionally, with _response polymorphism_, the _response_ can be extended to
 provide better contextual information regarding the result, such as parsing the _response_ body as
 JSON or converting the _response_ body into a `UIImage`.

 The way you deal with a _TNLResponse_ should be systematic and straighforward:

 1. deal with any errors on the _response_
    - _TNLResponse_ has an _operationError_ property but custom subclasses could expose other errors too.
    - Subclass _response_ objects that have extra errors should consider having an `anyError` property for quick access to any error in the response.
 2. deal with the status code of the _response_
    - It is important to know that a 404 is not an _operation_ error so it won't be set as an error.
    - It is actually the status of the successful operation and needs to be handled accordingly.
    - For designs that want to treat HTTP Status codes that are not success as errors, they should expose an HTTP error on their _response_ subclass(es).
 3. deal with the _response_ payload
    - This could be the _response_ HTTP headers, the _response_ body (as `NSData` or a file on disk), etc
    - _response_ subclasses should consider deserializing their response's body into a model object and exposing it as a property for concrete interactions.

 One benefit to using _response polymorphism_ is the ability to handle the _response_ and populate
 the _hydrated response_ with the information that's pertinent to the caller.
 For example: if your network operation yields JSON, and all you care about is if that JSON came
 through or not, at hydration time you could check for any error conditions then parse out the JSON
 and if everything is good have a property on the custom `TNLResponse` subclasss that holds the
 `NSDictionary` _result_ property (or `nil` if anything along the way prevented success).

 Things you can inspect on a _response_ by default:

 - the _operation_ error (if one occurred)
 - the _original request_
 - the _response_ info
   - this object encapsulates the information of the _HTTP response_ including:
     - the source of the _response_ (local cache or network load)
     - the _response_ body (as `data` or `temporarySavedFile` if the _operation_ was configured to maintain the data)
     - the final `NSURLRequest` that loaded the _response_
     - the final `NSURLResponse` object
   - it also provides convenience accessors
     - the _response_'s _HTTP_ status code
     - the final `NSURL`
     - all the _HTTP_ header fields
 - the _response_ metrics
   - detailed metric information such as execution timings, durations, bytes sent/received, attempt counts, etc.
   - this is the detail that __TNL__ exposes for every _request_/_operation_/_response_ that really empowers programmers to maximize impact with their networking.

## Simple Network Operations

 __Twitter Network Layer__ provides a highly robust API for building network operations with a great
 deal of flexibility and extensibility.  However, there are often occasions when you just need to
 execute an _operation_ and need things to be as simple as possible.  __Twitter Network Layer__
 provides all the convenience necessary for getting what needs to be done as simply as possible.

```
 NSString *URLString = [NSURL URLWithString:@"http://api.myapp.com/settings"];
 NSURLRequest *request = [NSURLRequest requestWithURL:URLString];
 [[TNLRequestOperationQueue defaultOperationQueue] enqueueRequest:request
                                                       completion:^(TNLRequestOperation *op, TNLResponse *response) {
     NSDictionary *json = nil;
     if (!response.operationError && response.info.statusCode == 200) {
         json = [NSJSONSerialization JSONObjectWithData:response.info.data options:0 error:NULL];
     }
     if (json) {
        [self _myapp_didCompleteSettingsRequestWithJSON:json];
     } else {
        [self _myapp_didFailSettingsRequest];
     }
 }];
```

 ## Configuring Behavior

 Often the vanila _configuration_ for an _operation_ will suffice, however it is common to need
 particular behaviors in order to get specific use cases to work.  Let's take, as an example, firing
 _network operation_ when a specific metric is hit.  In this case, we don't care about storing the
 _response_ body and we also want to avoid having a cache that could get in the way.

```
 NSURL *URL = [NSURL URLWithString:@"http://api.myapp.com/recordMetric?hit=true"];
 TNLHTTPRequest *request = [TNLHTTPRequest GETRequestWithURL:URL HTTPHeaderFields:nil];
 TNLMutableRequestConfiguration *config = [TNLMutableRequestConfiguration defaultConfiguration];
 config.responseDataConsumptionMode = TNLResponseDataConsumptionModeNone;
 config.URLCache = nil; // Note: 'URLCache' is now 'nil' by default in TNL, but the illustration still works
 TNLRequestOperation *op = [TNLRequestOperation operationWithRequest:request
                                                       configuration:config
                                                          completion:^(TNLRequestOperation *o, TNLResponse *response) {
     assert(response.info.source != TNLResponseSourceLocalCache);
     const BOOL success = response.info.statusCode == 202;
     [self didSendMetric:success];
 }];
 [[TNLRequestOperationQueue defaultOperationQueue] enqueueOperation:op];
```

 Now, sometimes, you may want to have the same defaults for certain kinds of _operations_.  That can
 easily be accomplished with a category or some other shared accessor.

```
 @interface TNLRequestConfiguration (APPAdditions)
 + (instancetype)configurationForMetricsFiring;
 @end

 @implementation TNLRequestConfiguration (APPAdditions)

 + (instancetype)configurationForMetricsFiring
 {
     static TNLRequestConfiguration* sConfig;
     static dispatch_once_t onceToken;
     dispatch_once(&onceToken, ^{
         TNLMutableRequestConfiguration *mConfig = [TNLMutableRequestConfiguration defaultConfiguration];
         mConfig.URLCache = nil; // Note: 'URLCache' is now 'nil' by default in TNL, but the illustration still works
         mConfig.responseDataConsumptionMode = TNLResponseDataConsumptionModeNone;
         sConfig = [mConfig copy];
     });
     return sConfig;
 }

 @end

 @implementation TNLMutableRequestConfiguration (APPAdditions)

 + (instancetype)configurationForMetricsFiring
 {
     return [[TNLRequestConfiguration configurationForMetricsFiring] mutableCopy];
 }

 @end
```

## Building an Advanced API Layer

 __Twitter Network Layer__ was designed from the ground up with REST APIs in mind.  From simple APIs
 to complex API layers that require a complicated system for managing all _operations_, __TNL__
 provides the foundation needed.

 As a pattern for creating concrete _API operations_, one of the first places to extend __TNL__ for
 your API layer is by concretely building API _requests_ and _responses_.  For _requests_, you
 implement a `TNLRequest` for every _request_ your API provides with properties that configure each
 request appropriately.  Those _requests_ should be subclassing a _base request_ that does the busy
 work of pulling together the generic properties that the subclasses can override to construct the
 _HTTP_ properties of the _request_.  Each subclassed _request_ then overrides only what is
 necessary to form the valid _HTTP_ request.  For things that are context or time sensitive, such as
 _request signing_, _request hydration_ should be used to fully saturate the custom _API request_ at
 the time the _request_ is going to sent (vs at the time it was enqueued).

 Following from custom _API requests_ are custom _API responses_.  At a minimum, it makes sense to
 have an _API response_ that subclasses `TNLResponse`.   To provide an even simpler interface to
 callers, you can implement a _response_ per _request_.  For _response hydration_, you merely
 extract whatever contextually relevant information is valuable for an _API response_ and set those
 properties on you custom subclass of `TNLResponse` (such as API error, JSON result, etc).

 If the API layer is advanced enough, it may warrant further encapsulation with a managing object
 which is often referred to as an _API client_.  The _API client_ would manage the queuing of
 _requests_, the delegate implementation for _operations_ (including _hydration_ for _requests_ and
 subclassing _responses_ so they hydrate too), the vending of _operations_, authentication/signing
 of _requests_, high level retry plus timeout behavior, custom _configurations_ and oberving
 _responses_ for custom handling.

### Client Architecture

 With an _API client_ architecture, the entire _HTTP_ structure is encapsulated and callers can deal
 with things just the objects they care about.  No converting or validating.  No configuring.  The
 power of __TNL__ is completely utilized by _API client_ freeing the caller of any burden.

```
 APISendMessageRequest *request = [[APISendMessageRequest alloc] init];
 request.sender = self.user;
 request.receiver = otherUser;
 request.message = message;
 self.sendOp = [[APIClient sharedInstance] enqueueRequest:request
                                           completion:^(TNLRequestOperation *op, APIResponse *response) {
    [weakSelf messageSendDidComplete:op withResponse:(id)response];
 }];

 // ... elsewhere ...

 - (void)messageSendDidComplete:(TNLRequestOperation *)op withResponse:(APISendMessageResponse *)response
 {
     assert(self.sendOp == op);
     self.sendOp = nil;
     if (!sendMessageResponse.wasCancelled) {
        if (sendMessageResponse.succeeded) {
            [self updateUIForCompletedMessageSendWithId:sendMessageResponse.messageId];
        } else {
            [self updateUIForFailedMessageSendWithUserErrorTitle:sendMessageResponse.errorTitle
                                                    errorMessage:sendMessageResponse.errorMessage];
        }
     }
 }

 // Insight:
 // Presumably, APISendMessageResponse would subclass a base response like APIBaseResponse.
 // Following that presumption, it would make sense that APIBaseResponse would expose
 // wasCancelled, succeeded, errorTitle and errorMessage while APISendMessageResponse would
 // expose messageId (since that is part of the response payload that is specific to the request).
 // It would likely make sense that if the API used JSON response bodies,
 // the base response would also expose a "result" property (NSDictionary) and
 // APISendMessageResponse's implementation for messageId is just:
 //    return self.result[@"newMessageId"];
```

## Using the Command-Line-Interface

__Twitter Network Layer__ includes a target for building a _macOS_ tool called `tnlcli`.  You can build this tool
run it from _Terminal_ from you _Mac_, similar to _cURL_ or other networking command line utilities.

### Usage

```
Usage: tnlcli [options] url

    Example: tnlcli --request-method HEAD --response-header-mode file,print --response-header-file response_headers.json https://google.com

Argument Options:
-----------------

    --request-config-file <filepath>     TNLRequestConfiguration as a json file
    --request-headers-file <filepath>    json file of key-value-pairs for using as headers
    --request-body-file <filepath>       file for the HTTP body

    --request-header "Field: Value"      A header to provide with the request (will override the header if also in the request header file). Can provide multiple headers.
    --request-config "config: value"     A config setting for the TNLRequestConfiguration of the request (will override the config if also in the request config file). Can provide multiple configs.
    --request-method <method>            HTTP Method from Section 9 in HTTP/1.1 spec (RFC 2616), such as GET, POST, HEAD, etc

    --response-body-mode <mode>          "file" or "print" or a combo using commas
    --response-body-file <filepath>      file for the response body to save to (requires "file" for --response-body-mode
    --response-headers-mode <mode>       "file" or "print" or a combo using commas
    --response-headers-file <filepath>   file for the response headers to save to (as json)

    --dump-cert-chain-directory <dir>    directory for the certification chain to be dumped to (as DER files)

    --verbose                            Will print verbose information and force the --response-body-mode and --responde-headers-mode to have "print".
    --version                            Will print ther version information.
```

# License

Copyright 2014-2020 Twitter, Inc.

Licensed under the Apache License, Version 2.0: https://www.apache.org/licenses/LICENSE-2.0

# Security Issues?

Please report sensitive security issues via Twitter's bug-bounty program (https://hackerone.com/twitter) rather than GitHub.

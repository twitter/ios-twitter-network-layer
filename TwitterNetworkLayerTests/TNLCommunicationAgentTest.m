//
//  TNLCommunicationAgentTest.m
//  TwitterNetworkLayer
//
//  Created by Nolan on 4/29/20.
//  Copyright © 2020 Twitter. All rights reserved.
//

#import "TNLCommunicationAgent.h"

@import XCTest;

#define TEST_COMM_AGENT 0

@interface TNLCommunicationAgentTest : XCTestCase
@end

// This "test" mostly just excercises the communication agent and logs the state.
// It is best to avoid the network interfaces of a machine during unit tests,
// so this "test" is disable but available for local testing by setting TEST_COMM_AGENT to 1.
@implementation TNLCommunicationAgentTest

#if TEST_COMM_AGENT
- (void)testCommunicationAgent
{
    TNLCommunicationAgent *agent = [[TNLCommunicationAgent alloc] initWithInternetReachabilityHost:@"api.twitter.com"];

    XCTestExpectation *reachExpectation = [self expectationWithDescription:@"reachability"];
    [agent identifyReachability:^(TNLNetworkReachabilityFlags flags, TNLNetworkReachabilityStatus status) {
        [reachExpectation fulfill];
    }];
    XCTestExpectation *carrierExpectation = [self expectationWithDescription:@"carrier"];
    [agent identifyCarrierInfo:^(id<TNLCarrierInfo>  _Nullable info) {
        [carrierExpectation fulfill];
    }];
    XCTestExpectation *radioExpectation = [self expectationWithDescription:@"radio"];
    [agent identifyWWANRadioAccessTechnology:^(NSString * _Nullable info) {
        [radioExpectation fulfill];
    }];
    XCTestExpectation *captivePortalExpectation = [self expectationWithDescription:@"captive.portal"];
    [agent identifyCaptivePortalStatus:^(TNLCaptivePortalStatus status) {
        [captivePortalExpectation fulfill];
    }];

    [self waitForExpectations:@[reachExpectation,
                                carrierExpectation,
                                radioExpectation,
                                captivePortalExpectation]
                      timeout:10.0];

    NSLog(@"Reach.Status: %@", TNLNetworkReachabilityStatusToString(agent.currentReachabilityStatus));
    NSLog(@"Reach.Flags:  %@", TNLDebugStringFromNetworkReachabilityFlags(agent.currentReachabilityFlags));
    NSLog(@"Radio.Tech:   %@", agent.currentWWANRadioAccessTechnology);
    NSLog(@"Carrier:      %@", agent.currentCarrierInfo);
    NSLog(@"Captive:      %@", TNLCaptivePortalStatusToString(agent.currentCaptivePortalStatus));
}
#endif // TEST_COMM_AGENT

@end

//
//  TNLXAppDelegate.h
//  TNLExample
//
//  Created on 7/24/14.
//  Copyright © 2020 Twitter. All rights reserved.
//

@import UIKit;

FOUNDATION_EXTERN NSString *TNLXCommunicationStatusUpdatedNotification;

@interface TNLXAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

- (NSString *)communicationStatusDescription;

@end

#define APP_DELEGATE ((TNLXAppDelegate *)[[UIApplication sharedApplication] delegate])

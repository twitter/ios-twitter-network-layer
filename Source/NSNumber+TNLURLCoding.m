//
//  NSNumber+TNLURLCoding.m
//  TwitterNetworkLayer
//
//  Created on 9/17/15.
//  Copyright © 2015 Twitter. All rights reserved.
//

#import "NSNumber+TNLURLCoding.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSNumber (TNLURLCoding)

- (BOOL)tnl_isBoolean
{
    if ((__bridge void *)self == (void *)kCFBooleanTrue) {
        return YES;
    } else if ((__bridge void *)self == (void *)kCFBooleanFalse) {
        return YES;
    }

    return NO;
}

- (TNLBoolean *)tnl_booleanObject
{
    return [[TNLBoolean alloc] initWithBool:self.boolValue];
}

@end

@implementation TNLBoolean

- (instancetype)init
{
    return [self initWithBool:NO];
}

- (instancetype)initWithBool:(BOOL)boolValue
{
    if (self = [super init]) {
        _boolValue = boolValue;
    }
    return self;
}

- (nullable NSString *)tnl_URLEncodableStringValue
{
    return self.stringValue;
}

- (NSString *)stringValue
{
    return self.boolValue ? @"true" : @"false";
}

- (NSNumber *)numberValue
{
    return [NSNumber numberWithBool:self.boolValue];
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }

    if ([other isKindOfClass:[TNLBoolean class]]) {
        return self.boolValue == [(TNLBoolean *)other boolValue];
    }

    return NO;
}

- (NSUInteger)hash
{
    return (NSUInteger)self.boolValue;
}

@end

NS_ASSUME_NONNULL_END

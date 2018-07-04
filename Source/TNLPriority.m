//
//  TNLPriority.m
//  TwitterNetworkLayer
//
//  Created on 7/17/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <sys/sysctl.h>
#import "TNL_Project.h"
#import "TNLPriority.h"

NS_ASSUME_NONNULL_BEGIN

TNLPriority TNLConvertQueuePriorityToTNLPriority(NSOperationQueuePriority pri)
{
    switch (pri) {
        case NSOperationQueuePriorityVeryLow:
            return TNLPriorityVeryLow;
        case NSOperationQueuePriorityLow:
            return TNLPriorityLow;
        case NSOperationQueuePriorityNormal:
            return TNLPriorityNormal;
        case NSOperationQueuePriorityHigh:
            return TNLPriorityHigh;
        case NSOperationQueuePriorityVeryHigh:
            return TNLPriorityVeryHigh;
        default:
            break;
    }

    if (pri < NSOperationQueuePriorityVeryLow) {
        return TNLPriorityVeryLow;
    }
    if (pri < NSOperationQueuePriorityNormal) {
        return TNLPriorityLow;
    }
    if (pri > NSOperationQueuePriorityVeryHigh) {
        return TNLPriorityVeryHigh;
    }
    if (pri > NSOperationQueuePriorityNormal) {
        return TNLPriorityHigh;
    }

    TNLAssertNever();
    return TNLPriorityNormal;
}

static const float sFloatPriorityBucketOffset = 0.1f;
static const float sFloatPriorityBucketSize = (1.0f - (2.0f * sFloatPriorityBucketOffset)) / 5.0f;

TNLPriority TNLConvertURLSessionTaskPriorityToTNLPriority(float pri)
{
    if (pri < sFloatPriorityBucketOffset + sFloatPriorityBucketSize) {
        return TNLPriorityVeryLow;
    } else if (pri < sFloatPriorityBucketOffset + (sFloatPriorityBucketSize * 2.0f)) {
        return TNLPriorityLow;
    } else if (pri < sFloatPriorityBucketOffset + (sFloatPriorityBucketSize * 3.0f)) {
        return TNLPriorityNormal;
    } else if (pri < sFloatPriorityBucketOffset + (sFloatPriorityBucketSize * 4.0f)) {
        return TNLPriorityHigh;
    }
    return TNLPriorityVeryHigh;
}

TNLPriority TNLConvertQualityOfServiceToTNLPriority(NSQualityOfService qos)
{
    if (qos == NSQualityOfServiceDefault) {
        qos = (NSQualityOfServiceUserInitiated + NSQualityOfServiceUtility) / 2;
    }

    // Below I will denote how much of the range of possibilities remain with comments
    // [] == bounded inclusive
    // () == bounded exclusive
    // Example:
    //    [Val1...Val2) == "from Val1 inclusive to Val2 exclusive"


    // [INF...INF]

    if (qos > NSQualityOfServiceUserInitiated) {
        return TNLPriorityVeryHigh + 1;
    }

    // [INF...UserInitiated]

    if (qos < NSQualityOfServiceBackground) {
        return TNLPriorityVeryLow - 1;
    }

    // [Background...UserInitiated]

    if (qos < NSQualityOfServiceUtility) {
        return TNLPriorityVeryLow;
    }

    // [Utility...UserInitiated]

    if (qos == NSQualityOfServiceUtility) {
        return TNLPriorityLow;
    }

    // (Utility...UserInitiated]

    if (qos <= ((NSQualityOfServiceUserInitiated + NSQualityOfServiceUtility) / 2)) {
        return TNLPriorityNormal;
    }

    // (Default...UserInitiated]

    return TNLPriorityHigh;
}

TNLPriority TNLConvertGCDQOSToTNLPriority(qos_class_t gcdQOS)
{
    if (gcdQOS == QOS_CLASS_DEFAULT) {
        return (QOS_CLASS_USER_INITIATED + QOS_CLASS_UTILITY) / 2;
    }

    // Below I will denote how much of the range of possibilities remain with comments
    // [] == bounded inclusive
    // () == bounded exclusive
    // Example:
    //    [Val1...Val2) == "from Val1 inclusive to Val2 exclusive"


    // [INF...INF]

    if (gcdQOS > QOS_CLASS_USER_INITIATED) {
        return TNLPriorityVeryHigh + 1;
    }

    // [INF...UserInitiated]

    if (gcdQOS < QOS_CLASS_BACKGROUND) {
        return TNLPriorityVeryLow - 1;
    }

    // [Background...UserInitiated]

    if (gcdQOS < QOS_CLASS_UTILITY) {
        return TNLPriorityVeryLow;
    }

    // [Utility...UserInitiated]

    if (gcdQOS == QOS_CLASS_UTILITY) {
        return TNLPriorityLow;
    }

    // (Utility...UserInitiated]

    if (gcdQOS <= ((QOS_CLASS_USER_INITIATED + QOS_CLASS_UTILITY) / 2)) {
        return TNLPriorityNormal;
    }

    // (Default...UserInitiated]

    return TNLPriorityHigh;
}

TNLPriority TNLConvertGCDPriorityToTNLPriority(dispatch_queue_priority_t priority)
{
    if (priority == DISPATCH_QUEUE_PRIORITY_DEFAULT) {
        return TNLPriorityNormal;
    }

    if (priority > DISPATCH_QUEUE_PRIORITY_HIGH) {
        return TNLPriorityVeryHigh;
    }
    if (priority > DISPATCH_QUEUE_PRIORITY_DEFAULT) {
        return TNLPriorityHigh;
    }

    if (priority < DISPATCH_QUEUE_PRIORITY_LOW) {
        return TNLPriorityVeryLow;
    }
    if (priority < DISPATCH_QUEUE_PRIORITY_DEFAULT) {
        return TNLPriorityLow;
    }

    TNLAssertNever();
    return TNLPriorityNormal;
}

NSOperationQueuePriority TNLConvertTNLPriorityToQueuePriority(TNLPriority pri)
{
    switch (pri) {
        case TNLPriorityVeryLow:
            return NSOperationQueuePriorityVeryLow;
        case TNLPriorityLow:
            return NSOperationQueuePriorityLow;
        case TNLPriorityNormal:
            return NSOperationQueuePriorityNormal;
        case TNLPriorityHigh:
            return NSOperationQueuePriorityHigh;
        case TNLPriorityVeryHigh:
            return NSOperationQueuePriorityVeryHigh;
        default:
            break;
    }

    if (pri < TNLPriorityVeryLow) {
        return NSOperationQueuePriorityVeryLow;
    }
    if (pri > TNLPriorityVeryHigh) {
        return NSOperationQueuePriorityVeryHigh;
    }

    TNLAssertNever();
    return NSOperationQueuePriorityNormal;
}

dispatch_queue_priority_t TNLConvertTNLPriorityToGCDPriority(TNLPriority pri)
{
    switch (pri) {
        case TNLPriorityVeryHigh:
            return DISPATCH_QUEUE_PRIORITY_HIGH + 1;
        case TNLPriorityHigh:
            return DISPATCH_QUEUE_PRIORITY_HIGH;
        case TNLPriorityNormal:
            return DISPATCH_QUEUE_PRIORITY_DEFAULT;
        case TNLPriorityLow:
            return DISPATCH_QUEUE_PRIORITY_LOW;
        case TNLPriorityVeryLow:
            return DISPATCH_QUEUE_PRIORITY_BACKGROUND;
        default:
            break;
    }

    if (pri > TNLPriorityVeryHigh) {
        return DISPATCH_QUEUE_PRIORITY_HIGH + 2;
    }
    if (pri < TNLPriorityVeryLow) {
        return DISPATCH_QUEUE_PRIORITY_BACKGROUND;
    }

    TNLAssertNever();
    return DISPATCH_QUEUE_PRIORITY_DEFAULT;
}

float TNLConvertTNLPriorityToURLSessionTaskPriority(TNLPriority pri)
{
    switch (pri) {
        case TNLPriorityVeryLow:
            return 0.1f;
        case TNLPriorityLow:
            return 0.3f;
        case TNLPriorityNormal:
            return 0.5f;
        case TNLPriorityHigh:
            return 0.7f;
        case TNLPriorityVeryHigh:
            return 0.9f;
        default:
            break;
    }

    TNLStaticAssert(0.1f < sFloatPriorityBucketOffset + sFloatPriorityBucketSize, Miss_Matched_Priority_Buckets);
    TNLStaticAssert(0.3f < sFloatPriorityBucketOffset + (sFloatPriorityBucketSize * 2.0), Miss_Matched_Priority_Buckets);
    TNLStaticAssert(0.5f < sFloatPriorityBucketOffset + (sFloatPriorityBucketSize * 3.0), Miss_Matched_Priority_Buckets);
    TNLStaticAssert(0.7f < sFloatPriorityBucketOffset + (sFloatPriorityBucketSize * 4.0), Miss_Matched_Priority_Buckets);
    TNLStaticAssert(0.9f > sFloatPriorityBucketOffset + (sFloatPriorityBucketSize * 4.0), Miss_Matched_Priority_Buckets);

    if (pri < TNLPriorityVeryLow) {
        return 0.0f;
    }
    if (pri > TNLPriorityVeryHigh) {
        return 1.0f;
    }

    TNLAssertNever();
    return 0.5f;
}

NSQualityOfService TNLConvertTNLPriorityToQualityOfService(TNLPriority pri)
{

    /*

     VLo              Lo              Nml             Hi              VHi
     -2              -1                0               1               2
      9              17               21              25              33
     Bg              Uti                             UIni            UInt

     */

    switch (pri) {
        case TNLPriorityVeryHigh:
            return NSQualityOfServiceUserInteractive;
        case TNLPriorityHigh:
            return NSQualityOfServiceUserInitiated;
        case TNLPriorityNormal:
            return ((NSQualityOfServiceUserInitiated - NSQualityOfServiceUtility) / 2) + NSQualityOfServiceUtility;
        case TNLPriorityLow:
            return NSQualityOfServiceUtility;
        case TNLPriorityVeryLow:
            return NSQualityOfServiceBackground;
        default:
            break;
    }

    if (pri < TNLPriorityVeryLow) {
        return NSQualityOfServiceBackground - 1;
    }
    if (pri > TNLPriorityVeryHigh) {
        return NSQualityOfServiceUserInteractive + 1;
    }

    TNLAssertNever();
    return NSQualityOfServiceDefault;
}

qos_class_t TNLConvertTNLPriorityToGCDQOS(TNLPriority pri)
{
    switch (pri) {
        case TNLPriorityVeryLow:
            return QOS_CLASS_BACKGROUND;
        case TNLPriorityLow:
            return QOS_CLASS_UTILITY;
        case TNLPriorityHigh:
            return QOS_CLASS_USER_INITIATED;
        case TNLPriorityVeryHigh:
            return QOS_CLASS_USER_INTERACTIVE;
        case TNLPriorityNormal:
            return QOS_CLASS_DEFAULT;
        default:
            break;
    }

    if (pri < TNLPriorityVeryLow) {
        return QOS_CLASS_BACKGROUND;
    } else if (pri > TNLPriorityVeryHigh) {
        return QOS_CLASS_USER_INTERACTIVE;
    }

    TNLAssertNever();
    return QOS_CLASS_DEFAULT;
}

NSTimeInterval TNLDeferrableIntervalForPriority(TNLPriority pri)
{
    switch (pri) {
        case TNLPriorityVeryLow:
            return 60.0;
        case TNLPriorityLow:
            return 10.0;
        case TNLPriorityNormal:
        case TNLPriorityHigh:
        case TNLPriorityVeryHigh:
            break;
    }

    return 0.0;
}

NS_ASSUME_NONNULL_END

#import "ReplyTypes.h"

NSString * const RCErrorDomain = @"com.wcsy.reply.error";

NSError *RCError(RCErrorCode code) {
    return [NSError errorWithDomain:RCErrorDomain code:code userInfo:nil];
}

@implementation RCMessage
@end
@implementation RCSessionHandle
@end
@implementation RCContextSnapshot
@end
@implementation RCDecisionResult
@end
@implementation RCCandidate
@end

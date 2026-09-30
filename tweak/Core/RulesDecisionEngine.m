#import "RulesDecisionEngine.h"

@implementation RCRulesDecisionEngine
- (RCDecisionResult *)decide:(RCContextSnapshot *)snapshot {
    RCDecisionResult *result = [RCDecisionResult new];
    result.schemaVersion = 1;
    result.providerId = @"rules";
    result.modelVersion = @"1";
    result.replyNeed = @"uncertain";
    result.intent = @"other";
    result.tone = @"neutral";
    result.risk = @"unknown";
    result.strategy = @"clarify";
    result.confidence = @{ @"replyNeed": @0.4, @"intent": @0.3,
                           @"tone": @0.4, @"risk": @0.2, @"strategy": @0.5 };
    RCMessage *last = snapshot.messages.lastObject;
    if (!last || [last.direction isEqualToString:@"outgoing"] ||
        [last.direction isEqualToString:@"system"] || last.recalled) {
        result.replyNeed = @"no_reply";
        result.confidence = @{ @"replyNeed": @0.8, @"intent": @0.3,
                               @"tone": @0.4, @"risk": @0.2, @"strategy": @0.5 };
        return result;
    }
    NSString *text = [last.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![last.kind isEqualToString:@"text"] || !text.length) return result;
    if ([text containsString:@"？"] || [text containsString:@"?"] || [text hasSuffix:@"吗"] ||
        [text hasSuffix:@"么"]) {
        result.replyNeed = @"reply";
        result.intent = @"question";
        result.confidence = @{ @"replyNeed": @0.7, @"intent": @0.65,
                               @"tone": @0.4, @"risk": @0.2, @"strategy": @0.55 };
    } else if ([text isEqualToString:@"你好"] || [text isEqualToString:@"谢谢"] ||
               [text isEqualToString:@"早上好"] || [text isEqualToString:@"晚上好"]) {
        result.replyNeed = @"optional";
        result.intent = @"social";
        result.tone = @"warm";
        result.risk = @"normal";
        result.strategy = @"acknowledge";
        result.confidence = @{ @"replyNeed": @0.75, @"intent": @0.85,
                               @"tone": @0.7, @"risk": @0.6, @"strategy": @0.7 };
    }
    return result;
}
@end

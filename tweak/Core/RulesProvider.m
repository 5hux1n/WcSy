#import "RulesProvider.h"

@implementation RCRulesProvider
- (NSArray<RCCandidate *> *)candidatesForSnapshot:(RCContextSnapshot *)snapshot decision:(RCDecisionResult *)decision {
    if ([decision.replyNeed isEqualToString:@"no_reply"]) return @[];
    RCMessage *lastIncoming = nil;
    for (RCMessage *message in [snapshot.messages reverseObjectEnumerator]) {
        if ([message.direction isEqualToString:@"incoming"]) { lastIncoming = message; break; }
    }
    if (!lastIncoming) return @[];
    NSString *body = [lastIncoming.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL media = ![lastIncoming.kind isEqualToString:@"text"] || body.length == 0;
    // Conservative local fallback: no invented facts and no claim to understand media.
    NSArray<NSString *> *texts = media ? @[
        @"我暂时没法确认这条消息的内容，可以用文字补充一下吗？",
        @"收到，我看过文字说明后再回复你。",
        @"方便简单描述一下你希望我关注的部分吗？"
    ] : @[
        @"收到，我看一下再回复你。",
        @"谢谢告诉我。你希望我先确认哪一部分？",
        @"我了解了，想先确认一下具体情况。"
    ];
    NSArray<NSString *> *styles = @[@"brief", @"warm", @"formal"];
    NSMutableArray<RCCandidate *> *candidates = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger i = 0; i < texts.count; i++) {
        RCCandidate *candidate = [RCCandidate new];
        candidate.identifier = NSUUID.UUID.UUIDString;
        candidate.text = texts[i];
        candidate.style = styles[i];
        candidate.snapshotHash = snapshot.snapshotHash;
        [candidates addObject:candidate];
    }
    return candidates;
}
@end

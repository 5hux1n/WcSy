#import <Foundation/Foundation.h>
#import "../tweak/Core/JevDecisionProvider.h"
#import "../tweak/Core/RemoteGenerationProvider.h"

int main(void) { @autoreleasepool {
    RCMessage *message = [RCMessage new];
    message.senderId = @"synthetic-peer";
    message.direction = @"incoming";
    message.kind = @"text";
    message.text = @"你好，周末有空吗？";
    RCContextSnapshot *snapshot = [RCContextSnapshot new];
    snapshot.messages = @[message];
    snapshot.snapshotHash = @"synthetic-snapshot";
    RCDecisionResult *decision = [RCDecisionResult new];
    decision.replyNeed = @"reply";
    decision.intent = @"question";
    decision.tone = @"warm";
    decision.risk = @"normal";
    decision.strategy = @"clarify";
    NSData *jev = RCBuildJevRequestBody(snapshot);
    NSData *deepSeek = RCBuildDeepSeekRequestBody(snapshot, decision, @"deepseek-flash");
    if (!jev || !deepSeek) return 1;
    id payload = @{ @"jev": [NSJSONSerialization JSONObjectWithData:jev options:0 error:nil],
                    @"deepseek": [NSJSONSerialization JSONObjectWithData:deepSeek options:0 error:nil] };
    NSData *output = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(output.bytes, 1, output.length, stdout);
    return 0;
} }

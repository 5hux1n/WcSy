#import <Foundation/Foundation.h>
#import "../tweak/Core/ContextEngine.h"
#import "../tweak/Core/JevDecisionProvider.h"
#import "../tweak/Core/DecisionSchema.h"

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    NSArray *fixtures = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
    if (![fixtures isKindOfClass:NSArray.class]) return 3;
    NSMutableArray *outputs = [NSMutableArray array];
    for (NSDictionary *fixture in fixtures) {
        RCSessionHandle *session = [RCSessionHandle new];
        session.sessionId = [fixture[@"type"] isEqual:@"group"] ? @"synthetic@chatroom" : @"synthetic-direct";
        session.pageToken = @"fixture";
        NSMutableArray *messages = [NSMutableArray array];
        for (NSArray *entry in fixture[@"messages"]) {
            RCMessage *message = [RCMessage new];
            message.localId = [@(messages.count + 1) stringValue];
            message.senderId = entry[0];
            message.direction = [entry[0] isEqual:@"self"] ? @"outgoing" : @"incoming";
            message.kind = entry.count == 3 ? entry[1] : @"text";
            message.text = entry.lastObject;
            message.partial = ![message.kind isEqual:@"text"];
            message.timestampMs = 1000 * (messages.count + 1);
            [messages addObject:message];
        }
        RCContextSnapshot *snapshot = [RCContextEngine buildWithMessages:messages session:session
            requestId:fixture[@"id"] limit:100 maxCharacters:16000];
        NSData *data = RCBuildJevRequestBody(snapshot);
        if (!data || data.length > 128000) return 4;
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([request[@"questions"] count] != 14 || request[@"questions"][@"strategy"]) return 5;
        if ([request[@"state"][@"target"][@"index"] unsignedIntegerValue] != messages.count - 1) return 6;
        NSString *wire = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([wire containsString:@"不可读取的图片正文"]) return 7;
        [outputs addObject:@{ @"id": fixture[@"id"], @"request": request, @"expected": fixture[@"expected"] }];
    }
    NSData *output = [NSJSONSerialization dataWithJSONObject:outputs options:0 error:nil];
    fwrite(output.bytes, 1, output.length, stdout);
    return 0;
} }

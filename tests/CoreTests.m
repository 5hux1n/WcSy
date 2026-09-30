#import <Foundation/Foundation.h>
#import "../tweak/Core/SessionCoordinator.h"
#import "../tweak/Core/ContextEngine.h"
#import "../tweak/Core/PrivacyGate.h"
#import "../tweak/Core/CandidateValidator.h"
#import "../tweak/Core/RemoteGenerationProvider.h"
#import "../tweak/Core/JevDecisionProvider.h"
#import "../tweak/Core/ConversationPolicy.h"
#import "../tweak/Core/MessageCursor.h"
#import "../tweak/Core/DecisionSchema.h"

@interface MockAdapter : NSObject <RCChatAdapter>
@property (nonatomic, strong) RCSessionHandle *session;
@property (nonatomic, copy) NSArray<RCMessage *> *messages;
@property (nonatomic, copy) NSString *draft;
@property (nonatomic, copy) NSString *filled;
@end
@implementation MockAdapter
- (RCSessionHandle *)currentSession { return self.session; }
- (NSArray<RCMessage *> *)recentMessagesForSession:(RCSessionHandle *)session limit:(NSUInteger)limit error:(NSError **)error {
    (void)error;
    if (![session.sessionId isEqualToString:self.session.sessionId]) return nil;
    NSUInteger count = MIN(limit, self.messages.count);
    return [self.messages subarrayWithRange:NSMakeRange(self.messages.count - count, count)];
}
- (NSString *)draftForSession:(RCSessionHandle *)session error:(NSError **)error {
    (void)error;
    return [session.pageToken isEqualToString:self.session.pageToken] ? self.draft : nil;
}
- (BOOL)fillDraft:(NSString *)text session:(RCSessionHandle *)session expectedHash:(NSString *)snapshotHash
   allowOverwrite:(BOOL)allowOverwrite error:(NSError **)error {
    (void)snapshotHash; (void)error;
    if (![session.pageToken isEqualToString:self.session.pageToken] || (self.draft.length && !allowOverwrite)) return NO;
    self.filled = text;
    self.draft = text;
    return YES;
}
@end

@interface FakeJevProvider : RCJevDecisionProvider
@property (nonatomic, copy) void (^pending)(RCDecisionResult *, NSError *);
@end
@implementation FakeJevProvider
- (NSURLSessionDataTask *)decide:(RCContextSnapshot *)snapshot
    completion:(void (^)(RCDecisionResult *, NSError *))completion {
    (void)snapshot;
    self.pending = completion;
    return nil;
}
@end

@interface FakeGenerationProvider : RCRemoteGenerationProvider
@property (nonatomic, copy) void (^pending)(NSArray<RCCandidate *> *, NSError *);
@property (nonatomic) NSUInteger calls;
@end
@implementation FakeGenerationProvider
- (NSURLSessionDataTask *)generate:(RCContextSnapshot *)snapshot decision:(RCDecisionResult *)decision
    completion:(void (^)(NSArray<RCCandidate *> *, NSError *))completion {
    (void)snapshot; (void)decision;
    self.calls++;
    self.pending = completion;
    return nil;
}
@end

static RCMessage *Message(NSString *identifier, NSString *text, long long time) {
    RCMessage *message = [RCMessage new];
    message.localId = identifier; message.senderId = @"person";
    message.direction = @"incoming"; message.kind = @"text";
    message.text = text; message.timestampMs = time;
    return message;
}
static MockAdapter *Adapter(void) {
    MockAdapter *adapter = [MockAdapter new];
    adapter.session = [RCSessionHandle new];
    adapter.session.sessionId = @"s1";
    adapter.session.pageToken = @"p1";
    adapter.messages = @[Message(@"1", @"你好", 1)];
    adapter.draft = @"";
    return adapter;
}
static void Drain(void) {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
#define CHECK(condition) do { if (!(condition)) { NSLog(@"FAIL at line %d", __LINE__); exit(1); } } while (0)

int main(void) { @autoreleasepool {
    MockAdapter *adapter = Adapter();
    RCSessionCoordinator *coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    [coordinator generate]; Drain();
    CHECK(coordinator.state == RCStateReady && coordinator.candidates.count == 3);
    NSError *error = nil;
    CHECK([coordinator fillCandidateAtIndex:0 allowOverwrite:NO error:&error]);
    CHECK(adapter.filled.length > 0 && coordinator.state == RCStateIdle);

    adapter = Adapter(); adapter.draft = @"我的草稿";
    coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    [coordinator generate]; Drain();
    error = nil;
    CHECK(![coordinator fillCandidateAtIndex:0 allowOverwrite:NO error:&error]);
    CHECK(error.code == RCErrorDraftPresent && !adapter.filled);
    error = nil;
    CHECK([coordinator fillCandidateAtIndex:0 allowOverwrite:YES error:&error]);

    adapter = Adapter(); coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    [coordinator generate];
    adapter.session.pageToken = @"p2";
    Drain();
    CHECK(coordinator.state == RCStateIdle && coordinator.candidates.count == 0);

    adapter = Adapter(); coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    [coordinator generate]; Drain();
    adapter.messages = @[Message(@"1", @"你好", 1), Message(@"2", @"新消息", 2)];
    error = nil;
    CHECK(![coordinator fillCandidateAtIndex:0 allowOverwrite:YES error:&error]);
    CHECK(!adapter.filled && coordinator.state == RCStateIdle);

    RCPrivacyGate *gate = [RCPrivacyGate new];
    gate.approvedHost = @"example.com";
    CHECK(![gate authorizeRemoteURL:[NSURL URLWithString:@"https://example.com/chat/completions"] error:nil]);
    gate.remoteEnabled = YES; gate.remoteConsent = YES;
    CHECK([gate authorizeRemoteURL:[NSURL URLWithString:@"https://example.com/chat/completions"] error:nil]);
    CHECK(![gate authorizeRemoteURL:[NSURL URLWithString:@"http://example.com/chat/completions"] error:nil]);
    CHECK(![gate authorizeRemoteURL:[NSURL URLWithString:@"https://other.com/chat/completions"] error:nil]);
    CHECK(![gate authorizeRemoteURL:[NSURL URLWithString:@"https://example.com/chat/completions?token=abc"] error:nil]);
    NSString *policyId = NSUUID.UUID.UUIDString;
    NSString *otherPolicyId = NSUUID.UUID.UUIDString;
    CHECK(!RCConversationEnabled(policyId) && !RCConversationEnabled(otherPolicyId));
    RCSetConversationEnabled(policyId, YES);
    CHECK(RCConversationEnabled(policyId) && !RCConversationEnabled(otherPolicyId));
    RCSetConversationEnabled(policyId, NO);
    CHECK(!RCConversationEnabled(policyId));
    RCRemoteGenerationProvider *remote = [[RCRemoteGenerationProvider alloc]
        initWithEndpoint:[NSURL URLWithString:@"https://example.com/chat/completions"] model:@"test" gate:gate];
    __block NSURLRequest *redirectDecision = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.com/"]];
    NSURLSession *testSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSURLSessionDataTask *testTask = [testSession dataTaskWithURL:[NSURL URLWithString:@"https://example.com/"]];
    NSHTTPURLResponse *redirect = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com/"]
        statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Location": @"https://other.com/" }];
    [remote URLSession:testSession task:testTask willPerformHTTPRedirection:redirect newRequest:redirectDecision
        completionHandler:^(NSURLRequest *request) { redirectDecision = request; }];
    CHECK(redirectDecision == nil);
    [testSession invalidateAndCancel];

    RCSessionHandle *session = Adapter().session;
    RCContextSnapshot *snapshot = [RCContextEngine buildWithMessages:@[Message(@"1", @"旧", 1), Message(@"2", @"新", 2)]
        session:session requestId:@"r" limit:1 maxCharacters:100];
    CHECK(snapshot.messages.count == 1 && [snapshot.messages[0].text isEqualToString:@"新"] && snapshot.partial);
    RCContextSnapshot *sameSecond = [RCContextEngine buildWithMessages:@[
        Message(@"9", @"先到", 1000), Message(@"10", @"后到", 1000)]
        session:session requestId:@"same-second" limit:20 maxCharacters:4000];
    CHECK([sameSecond.messages.lastObject.localId isEqualToString:@"10"]);
    RCMessage *longMessage = Message(@"long", [@"A" stringByPaddingToLength:5000 withString:@"A" startingAtIndex:0], 3);
    RCContextSnapshot *clipped = [RCContextEngine buildWithMessages:@[longMessage] session:session
        requestId:@"r" limit:20 maxCharacters:4000];
    CHECK(clipped.partial && clipped.messages[0].text.length <= 4000);
    NSString *oldHash = clipped.snapshotHash;
    longMessage.text = [@"B" stringByAppendingString:[longMessage.text substringFromIndex:1]];
    clipped = [RCContextEngine buildWithMessages:@[longMessage] session:session
        requestId:@"r" limit:20 maxCharacters:4000];
    CHECK(![oldHash isEqualToString:clipped.snapshotHash]);

    // Construct a complete provider response using the production vocabulary.
    NSMutableDictionary *answers = [NSMutableDictionary dictionary];
    NSDictionary *schema = RCJevAnalysisSchema();
    for (NSString *field in RCJevAnalysisFieldOrder()) {
        NSDictionary *options = schema[field][@"options"];
        NSArray *keys = [options.allKeys sortedArrayUsingSelector:@selector(compare:)];
        NSMutableDictionary *probabilities = [NSMutableDictionary dictionary];
        for (NSString *key in keys) probabilities[key] = @0;
        probabilities[keys[0]] = @0.6;
        probabilities[keys[1]] = @0.4;
        answers[field] = @{ @"type": @"choice", @"choice": keys[0], @"confidence": @0.5,
            @"probabilities": probabilities };
    }
    NSData *(^responseData)(NSDictionary *) = ^NSData *(NSDictionary *fields) {
        return [NSJSONSerialization dataWithJSONObject:@{ @"model": @"jev-1.13.0", @"answers": fields }
            options:0 error:nil];
    };
    RCDecisionResult *decision = RCParseJevDecisionResponse(responseData(answers));
    CHECK(decision && decision.schemaVersion == 2 && decision.judgments.count == 14);
    CHECK(decision.replyNeed == nil && decision.strategy == nil && decision.tone == nil);
    decision.contextMessageCount = 85;
    NSString *display = RCFormatJevAnalysis(decision);
    CHECK([display containsString:@"60%"] && [display containsString:@"40%"] && [display containsString:@"低置信"]);
    CHECK(![display containsString:@"建议"] && ![display containsString:@"先问清楚"]);
    CHECK([RCJevAnalysisPreview(display) hasPrefix:@"JEV："]);
    CHECK(![RCDisplayStoredAnalysis(@"JEV · 决策咨询\n回复：建议回复 · 意图：提问\n建议：先问清楚") containsString:@"建议"]);
    for (NSUInteger invalid = 0; invalid < 7; invalid++) {
        NSMutableDictionary *bad = [answers mutableCopy];
        NSMutableDictionary *answer = [bad[@"scene"] mutableCopy];
        if (invalid == 0) answer[@"choice"] = @"unsafe-value";
        if (invalid == 1) answer[@"confidence"] = @YES;
        if (invalid == 2) [answer removeObjectForKey:@"probabilities"];
        if (invalid == 3) answer[@"probabilities"] = @{ @"coordination": @1 };
        if (invalid == 4) {
            NSMutableDictionary *probabilities = [answer[@"probabilities"] mutableCopy];
            for (NSString *key in probabilities.allKeys) probabilities[key] = @0.9;
            answer[@"probabilities"] = probabilities;
        }
        if (invalid == 5) answer[@"choice"] = @"unknown"; // Not a maximum-probability option.
        bad[@"scene"] = answer;
        if (invalid == 6) [bad removeObjectForKey:@"gap"];
        CHECK(RCParseJevDecisionResponse(responseData(bad)) == nil);
    }

    // Full multi-speaker state, clear target, no account identifiers, no advice questions.
    NSMutableArray *history = [NSMutableArray array];
    for (NSUInteger i = 0; i < 100; i++) {
        RCMessage *item = Message([@(i + 1) stringValue], i == 0 ? @"周末由我安排餐厅" : @"随后交流", 1000 * (i + 1));
        item.direction = i % 2 == 0 ? @"outgoing" : @"incoming";
        item.senderId = i % 2 == 0 ? @"private-self-id" : @"private-peer-id";
        [history addObject:item];
    }
    RCContextSnapshot *extended = [RCContextEngine buildWithMessages:history session:session requestId:@"extended"
        limit:100 maxCharacters:16000];
    CHECK(extended.messages.count == 100);
    NSData *requestData = RCBuildJevRequestBody(extended);
    NSDictionary *requestBody = [NSJSONSerialization JSONObjectWithData:requestData options:0 error:nil];
    NSDictionary *requestState = requestBody[@"state"];
    CHECK([requestState[@"messages"] count] == 100 && [requestState[@"target"][@"index"] unsignedIntegerValue] == 99);
    CHECK([requestState[@"messages"][0][@"text"] isEqualToString:@"周末由我安排餐厅"]);
    CHECK([requestState[@"messages"][0][@"speaker"] isEqualToString:@"我"]);
    CHECK([requestState[@"messages"][1][@"secondsSincePrevious"] integerValue] == 1);
    NSString *requestText = [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding];
    CHECK(![requestText containsString:@"private-self-id"] && ![requestText containsString:@"private-peer-id"]);
    CHECK([requestBody[@"questions"] count] == 14 && !requestBody[@"questions"][@"strategy"]);
    CHECK(requestData.length < 128000);
    RCMessage *unread = Message(@"media", @"不得发送的已撤回正文", 1000000);
    unread.recalled = YES;
    extended.messages = @[unread];
    CHECK(![[[NSString alloc] initWithData:RCBuildJevRequestBody(extended) encoding:NSUTF8StringEncoding]
        containsString:@"不得发送的已撤回正文"]);

    NSData *deepSeekData = [NSJSONSerialization dataWithJSONObject:@{
        @"model": @"deepseek-flash", @"choices": @[@{ @"message": @{
            @"role": @"assistant", @"content": @"[\"你好呀！\", \"嗨，很高兴见到你！\"]" }}]
    } options:0 error:nil];
    NSArray<RCCandidate *> *parsed = RCParseDeepSeekResponse(deepSeekData, @"snapshot-1");
    CHECK(parsed.count == 2 && [parsed[0].text isEqualToString:@"你好呀！"] &&
        [parsed[1].snapshotHash isEqualToString:@"snapshot-1"]);
    NSData *jsonModeData = [NSJSONSerialization dataWithJSONObject:@{
        @"choices": @[@{ @"finish_reason": @"stop", @"message": @{
            @"content": @"{\"candidates\":[\"可以呀，周末哪天方便？\",\"这周末应该可以，你想做什么？\",\"我确认下安排，再告诉你好吗？\"]}" }}]
    } options:0 error:nil];
    CHECK(RCParseDeepSeekResponse(jsonModeData, @"snapshot-1").count == 3);
    NSData *cutoffData = [NSJSONSerialization dataWithJSONObject:@{
        @"choices": @[@{ @"finish_reason": @"length", @"message": @{
            @"content": @"{\"candidates\":[\"好的\",\"可以\"]}" }}]
    } options:0 error:nil];
    CHECK(RCParseDeepSeekResponse(cutoffData, @"snapshot-1") == nil);
    NSData *badDeepSeekData = [NSJSONSerialization dataWithJSONObject:@{
        @"choices": @[@{ @"message": @{ @"content": @"普通文本，不是 JSON 数组" }}]
    } options:0 error:nil];
    CHECK(RCParseDeepSeekResponse(badDeepSeekData, @"snapshot-1") == nil);

    adapter = Adapter();
    coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    FakeJevProvider *fakeJev = [FakeJevProvider new];
    FakeGenerationProvider *fakeGeneration = [FakeGenerationProvider new];
    coordinator.jevProvider = fakeJev;
    coordinator.remoteProvider = fakeGeneration;
    [coordinator generate];
    CHECK(coordinator.state == RCStateDeciding && fakeGeneration.calls == 0 && fakeJev.pending != nil);
    void (^lateDecision)(RCDecisionResult *, NSError *) = fakeJev.pending;
    [coordinator cancel];
    lateDecision(decision, nil);
    Drain();
    CHECK(coordinator.state == RCStateIdle && fakeGeneration.calls == 0);

    decision.replyNeed = @"reply"; // Candidate-generation test needs a reply decision.
    [coordinator generate];
    fakeJev.pending(decision, nil);
    Drain();
    CHECK(coordinator.state == RCStateGenerating && fakeGeneration.calls == 1 && fakeGeneration.pending != nil);
    void (^lateGeneration)(NSArray<RCCandidate *> *, NSError *) = fakeGeneration.pending;
    [coordinator cancel];
    lateGeneration(@[], nil);
    Drain();
    CHECK(coordinator.state == RCStateIdle && coordinator.candidates.count == 0);

    adapter = Adapter();
    coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    fakeJev = [FakeJevProvider new];
    coordinator.jevProvider = fakeJev;
    __block NSError *analysisError = nil;
    __block NSUInteger analysisCallbacks = 0;
    [coordinator analyzeLatestWithCompletion:^(RCMessage *message, RCDecisionResult *result, NSError *providerError) {
        (void)message; (void)result;
        analysisCallbacks++;
        analysisError = providerError;
    }];
    CHECK(fakeJev.pending != nil);
    void (^cancelledAnalysis)(RCDecisionResult *, NSError *) = fakeJev.pending;
    [coordinator cancel];
    cancelledAnalysis(decision, nil);
    Drain();
    CHECK(analysisCallbacks == 1 && analysisError.code == RCErrorCancelled);

    adapter = Adapter();
    coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    fakeJev = [FakeJevProvider new];
    coordinator.jevProvider = fakeJev;
    __block RCMessage *analyzed = nil;
    [coordinator analyzeMessageWithId:@"1" completion:^(RCMessage *message, RCDecisionResult *result, NSError *providerError) {
        (void)result; (void)providerError;
        analyzed = message;
    }];
    adapter.messages = @[adapter.messages[0], Message(@"2", @"稍后到的消息", 2)];
    fakeJev.pending(decision, nil);
    Drain();
    CHECK([analyzed.localId isEqualToString:@"1"]);

    // Old completions must not win over newer analysis requests.
    __block NSError *oldError = nil;
    __block NSUInteger newestCompletions = 0;
    [coordinator analyzeMessageWithId:@"1" completion:^(RCMessage *m, RCDecisionResult *r, NSError *e) {
        (void)m; (void)r; oldError = e;
    }];
    void (^superseded)(RCDecisionResult *, NSError *) = fakeJev.pending;
    [coordinator analyzeMessageWithId:@"2" completion:^(RCMessage *m, RCDecisionResult *r, NSError *e) {
        (void)r; CHECK(!e && [m.localId isEqualToString:@"2"]); newestCompletions++;
    }];
    superseded(decision, nil);
    fakeJev.pending(decision, nil); Drain();
    CHECK(oldError.code == RCErrorCancelled && newestCompletions == 1);

    // Capture session identity by value, even when adapters mutate the same handle.
    analysisError = nil;
    [coordinator analyzeMessageWithId:@"2" completion:^(RCMessage *m, RCDecisionResult *r, NSError *e) {
        (void)m; (void)r; analysisError = e;
    }];
    adapter.session.pageToken = @"replacement-page";
    fakeJev.pending(decision, nil); Drain();
    CHECK(analysisError.code == RCErrorStaleSession);

    // Sliding history must not discard an otherwise unchanged target.
    NSMutableArray *traffic = [NSMutableArray array];
    for (NSUInteger i = 1; i <= 100; i++) [traffic addObject:Message([@(i) stringValue], @"文字", i)];
    adapter.messages = traffic;
    analyzed = nil;
    [coordinator analyzeMessageWithId:@"100" completion:^(RCMessage *m, RCDecisionResult *r, NSError *e) {
        (void)r; CHECK(!e); analyzed = m;
    }];
    [traffic addObject:Message(@"101", @"新消息", 101)];
    adapter.messages = traffic;
    fakeJev.pending(decision, nil); Drain();
    CHECK([analyzed.localId isEqualToString:@"100"]);

    // A newly delivered message may carry an older server timestamp.
    adapter.messages = @[Message(@"120", @"先收到", 5000), Message(@"121", @"延后投递", 4000)];
    analyzed = nil;
    [coordinator analyzeMessageWithId:@"121" completion:^(RCMessage *m, RCDecisionResult *r, NSError *e) {
        (void)r; CHECK(!e); analyzed = m;
    }];
    fakeJev.pending(decision, nil); Drain();
    CHECK([analyzed.localId isEqualToString:@"121"]);

    // A target edit, recall or sender-direction change must still reject the result.
    for (NSUInteger mutation = 0; mutation < 3; mutation++) {
        adapter.messages = @[Message(@"30", @"原文", 30)];
        analysisError = nil;
        [coordinator analyzeMessageWithId:@"30" completion:^(RCMessage *m, RCDecisionResult *r, NSError *e) {
            (void)m; (void)r; analysisError = e;
        }];
        if (mutation == 0) adapter.messages[0].text = @"已编辑";
        if (mutation == 1) adapter.messages[0].recalled = YES;
        if (mutation == 2) adapter.messages[0].direction = @"outgoing";
        fakeJev.pending(decision, nil); Drain();
        CHECK(analysisError.code == RCErrorStaleSession);
    }

    RCMessageCursor *cursor = [[RCMessageCursor alloc] initWithMessages:@[] emptySince:1000];
    NSArray *firstArrival = @[Message(@"1", @"第一条", 1000)];
    CHECK([cursor consume:firstArrival].count == 1);
    CHECK([cursor consume:firstArrival].count == 0);
    // Burst moved the baseline out of the window; same-second IDs still advance.
    CHECK(([cursor consume:@[Message(@"22", @"连发", 1000), Message(@"23", @"连发", 1001)]].count == 2));
    CHECK([cursor consume:firstArrival].count == 0); // Loading old history isn't an arrival.
    CHECK([cursor consume:@[Message(@"24", @"新消息", 1002)]].count == 1);

    // New messages inserted before an unchanged trailing item were missed by 0.2.23.
    RCMessage *tail = Message(@"10", @"尾部原消息", 2000);
    cursor = [[RCMessageCursor alloc] initWithMessages:@[Message(@"9", @"旧消息", 1000), tail] emptySince:0];
    CHECK(([cursor consume:@[Message(@"9", @"旧消息", 1000), Message(@"11", @"新到消息", 3000), tail]].count == 1));
    CHECK(([cursor consume:@[Message(@"9", @"旧消息", 1000), Message(@"11", @"新到消息", 3000), tail]].count == 0));
    // Delayed server timestamps do not suppress a newly allocated local message ID.
    CHECK([cursor consume:@[Message(@"12", @"延迟投递", 1500)]].count == 1);
    RCMessage *placeholder = Message(@"13", @"", 4000);
    CHECK([cursor consume:@[placeholder]].count == 0);
    placeholder.text = @"内容加载完毕";
    CHECK([cursor consume:@[placeholder]].count == 1);

    // A clipping boundary through an emoji must remain valid UTF-8 and JSON.
    RCContextSnapshot *emoji = [RCContextEngine buildWithMessages:@[Message(@"emoji", @"A😀B", 1)]
        session:session requestId:@"emoji" limit:20 maxCharacters:34];
    CHECK(emoji.partial && [emoji.messages[0].text isEqualToString:@"B"]);
    CHECK(RCBuildJevRequestBody(emoji) != nil);

    adapter = Adapter(); adapter.messages[0].direction = @"outgoing";
    coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    [coordinator generate];
    CHECK(coordinator.state == RCStateNoReply && coordinator.candidates.count == 0);

    adapter = Adapter(); adapter.messages[0].kind = @"image"; adapter.messages[0].text = @"[非文字消息，内容未读取]";
    coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    __block NSError *mediaError = nil;
    coordinator.onChange = ^(RCState state, NSError *stateError) { if (state == RCStateError) mediaError = stateError; };
    [coordinator generate];
    CHECK(coordinator.state == RCStateError && mediaError.code == RCErrorUnsupportedContent);

    RCCandidate *unsafe = [RCCandidate new]; unsafe.text = @"访问 https://example.com"; unsafe.snapshotHash = @"h";
    RCCandidate *valid1 = [RCCandidate new]; valid1.text = @"好的"; valid1.snapshotHash = @"h";
    RCCandidate *valid2 = [RCCandidate new]; valid2.text = @"明白了"; valid2.snapshotHash = @"h";
    CHECK(([RCCandidateValidator validCandidates:@[unsafe, valid1, valid2] snapshotHash:@"h"].count == 2));
    NSLog(@"Core tests passed");
    return 0;
} }

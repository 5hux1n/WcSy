#import "ReplyOverlay.h"
#import "../Core/JevDecisionProvider.h"
#import "../Core/RemoteGenerationProvider.h"
#import "SettingsViewController.h"
#import "../WeChatAdapter/WeChatAdapter.h"
#import <math.h>
#import "../Core/MessageCursor.h"
#import "../Core/DecisionSchema.h"

static NSString *analysisRuntimeStatus = @"尚未进入已启用的聊天";
NSString *RCAnalysisRuntimeStatus(void) { return analysisRuntimeStatus; }

@interface RCReplyOverlay ()
@property (nonatomic, strong) RCSessionCoordinator *coordinator;
@property (nonatomic, copy) NSString *analysisStatus;
@property (nonatomic, copy) NSString *lastResultStatus;
@property (nonatomic, strong) NSDate *lastResultAt;
@property (nonatomic, strong) id settingsObserver;
@property (nonatomic, strong) NSTimer *analysisTimer;
@property (nonatomic, strong) RCMessageCursor *cursor;
@property (nonatomic) NSUInteger requestEpoch;
@property (nonatomic, copy) NSString *latestDecisionMessageId;
@property (nonatomic, strong) NSMutableArray<NSString *> *pendingMessageIds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *pendingSince;
@property (nonatomic, strong) NSMutableSet<NSString *> *processedMessageIds;
@property (nonatomic) BOOL analysisInFlight;
@property (nonatomic) NSTimeInterval lastAnalysisAt;
@property (nonatomic, copy) NSString *inFlightMessageId;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *attempts;
@end

@implementation RCReplyOverlay
- (void)setAnalysisStatus:(NSString *)status {
    _analysisStatus = [status copy];
    analysisRuntimeStatus = _analysisStatus; // Preserve the diagnostic export.
}

- (BOOL)isAnalyzing { return self.analysisInFlight; }

- (NSString *)statusSummary {
    NSMutableArray *lines = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"当前：%@", self.analysisStatus ?: @"等待新消息"]];
    if (self.analysisInFlight)
        [lines addObject:[NSString stringWithFormat:@"本次请求：已等待 %.0f 秒",
            MAX(0, NSDate.date.timeIntervalSince1970 - self.lastAnalysisAt)]];
    if (self.pendingMessageIds.count)
        [lines addObject:[NSString stringWithFormat:@"待分析：%lu 条", (unsigned long)self.pendingMessageIds.count]];
    if (self.lastResultStatus.length) {
        NSDateFormatter *format = [NSDateFormatter new];
        format.dateFormat = @"HH:mm:ss";
        [lines addObject:[NSString stringWithFormat:@"最近结果（%@）：%@",
            [format stringFromDate:self.lastResultAt], self.lastResultStatus]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)rememberResult:(NSString *)status {
    self.lastResultStatus = status;
    self.lastResultAt = NSDate.date;
}

- (instancetype)initWithCoordinator:(RCSessionCoordinator *)coordinator {
    if ((self = [super initWithFrame:CGRectZero])) {
        _coordinator = coordinator;
        _pendingMessageIds = [NSMutableArray array];
        _pendingSince = [NSMutableDictionary dictionary];
        _processedMessageIds = [NSMutableSet set];
        _attempts = [NSMutableDictionary dictionary];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self configureProvider];
        __weak typeof(self) weakSelf = self;
        _settingsObserver = [NSNotificationCenter.defaultCenter addObserverForName:RCSettingsChangedNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note;
                weakSelf.requestEpoch++;
                [weakSelf.coordinator cancel];
                weakSelf.analysisInFlight = NO;
                [weakSelf configureProvider];
                if (!RCSettingsEnabled()) [weakSelf detach];
            }];
    }
    return self;
}

- (void)configureProvider {
    self.coordinator.jevProvider = nil;
    if (!RCSettingsEnabled()) { self.analysisStatus = @"插件未启用"; return; }
    if (!RCLoadJevAPIKey().length) { self.analysisStatus = @"JEV 密钥未保存"; return; }
    RCPrivacyGate *gate = [RCPrivacyGate new];
    gate.approvedHost = @"api.typesafe.ai";
    gate.remoteEnabled = YES;
    gate.remoteConsent = YES; // Granted by the per-conversation consent alert.
    self.coordinator.jevProvider = [[RCJevDecisionProvider alloc] initWithGate:gate];
    self.analysisStatus = @"等待对方的新文字消息";
}

- (void)attachToChatView:(UIView *)chatView {
    [chatView addSubview:self];
    self.hidden = YES;
    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:chatView.leadingAnchor],
        [self.topAnchor constraintEqualToAnchor:chatView.topAnchor],
        [self.widthAnchor constraintEqualToConstant:0],
        [self.heightAnchor constraintEqualToConstant:0]
    ]];
    self.cursor = [[RCMessageCursor alloc] initWithMessages:self.coordinator.recentMessages
        emptySince:(long long)floor(NSDate.date.timeIntervalSince1970) * 1000];
    self.analysisTimer = [NSTimer timerWithTimeInterval:1.0 target:self
        selector:@selector(checkNewMessage) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.analysisTimer forMode:NSRunLoopCommonModes];
}

- (void)detach {
    self.requestEpoch++;
    self.analysisInFlight = NO;
    [self.analysisTimer invalidate];
    self.analysisTimer = nil;
    [self.coordinator cancel];
    [self.pendingMessageIds removeAllObjects];
    [self.pendingSince removeAllObjects];
    [self.processedMessageIds removeAllObjects];
    [self.attempts removeAllObjects];
    self.inFlightMessageId = nil;
    if (self.settingsObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.settingsObserver];
        self.settingsObserver = nil;
    }
    [self removeFromSuperview];
    self.analysisStatus = @"已离开聊天或关闭咨询";
}

- (void)forgetPending:(NSString *)messageId {
    [self.pendingMessageIds removeObject:messageId];
    [self.pendingSince removeObjectForKey:messageId];
    [self.processedMessageIds addObject:messageId];
}

- (void)reanalyzeLatestIncoming {
    for (RCMessage *message in [self.coordinator.recentMessages reverseObjectEnumerator]) {
        if (![message.kind isEqualToString:@"text"] || !message.text.length || message.recalled ||
            !message.localId.length || [message.localId hasPrefix:@"observed-"] ||
            RCMessageRenderDirection(message.localId) != 1) continue;
        [self.processedMessageIds removeObject:message.localId];
        [self.attempts removeObjectForKey:message.localId];
        if (![self.pendingMessageIds containsObject:message.localId]) {
            [self.pendingMessageIds insertObject:message.localId atIndex:0];
            self.pendingSince[message.localId] = NSDate.date;
        }
        self.analysisStatus = @"已请求重新分析最近的对方消息";
        [self checkNewMessage];
        return;
    }
    self.analysisStatus = @"当前没有可确认的对方文字消息";
}

- (void)checkNewMessage {
    if (!self.window || !RCSettingsEnabled()) return;
    RCRefreshInlineDecisions(self.latestDecisionMessageId);
    if (self.analysisInFlight && NSDate.date.timeIntervalSince1970 - self.lastAnalysisAt > 35) {
        self.requestEpoch++;
        [self.coordinator cancel];
        self.analysisInFlight = NO;
        self.inFlightMessageId = nil;
        self.analysisStatus = @"上次请求超时，队列已恢复";
        [self rememberResult:self.analysisStatus];
        NSLog(@"[WcSy] analysis watchdog released queue");
    }
    NSArray<RCMessage *> *recent = self.coordinator.recentMessages;
    RCMessage *latest = recent.lastObject;
    if (!latest.localId.length) { self.analysisStatus = @"当前消息列表暂不可读"; return; }
    for (RCMessage *message in [self.cursor consume:recent]) {
        if (![message.kind isEqualToString:@"text"] || !message.text.length || message.recalled ||
            !message.localId.length || [message.localId hasPrefix:@"observed-"] ||
            [self.processedMessageIds containsObject:message.localId] ||
            [self.pendingMessageIds containsObject:message.localId]) continue;
        [self.pendingMessageIds addObject:message.localId];
        self.pendingSince[message.localId] = NSDate.date;
        self.analysisStatus = @"新文字消息已入队，等待发送方向确认";
        NSLog(@"[WcSy] arrival queued pending=%lu", (unsigned long)self.pendingMessageIds.count);
    }
    // The cursor retains arrival order; old IDs outside this window need no set entry.
    NSMutableSet *retained = [NSMutableSet setWithArray:[recent valueForKey:@"localId"]];
    [retained addObjectsFromArray:self.pendingMessageIds];
    [self.processedMessageIds intersectSet:retained];
    for (NSString *identifier in self.attempts.allKeys)
        if (![retained containsObject:identifier] && ![identifier isEqualToString:self.inFlightMessageId])
            [self.attempts removeObjectForKey:identifier];
    while (self.pendingMessageIds.count > 20) [self forgetPending:self.pendingMessageIds.firstObject];
    for (NSString *identifier in [self.pendingMessageIds copy]) {
        NSInteger direction = RCMessageRenderDirection(identifier);
        if (direction == 0) {
            [self forgetPending:identifier];
            self.analysisStatus = @"自己的消息已跳过";
            continue;
        }
        if (direction < 0) {
            if ([NSDate.date timeIntervalSinceDate:self.pendingSince[identifier]] > 15) {
                [self forgetPending:identifier];
                self.analysisStatus = @"消息行方向无法确认，已跳过";
            }
            continue;
        }
        if (self.analysisInFlight) break;
        if (!self.coordinator.jevProvider) { self.analysisStatus = @"JEV 密钥未配置"; break; }
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        if (now - self.lastAnalysisAt < 2.0) break;
        self.lastAnalysisAt = now;
        [self forgetPending:identifier];
        self.analysisInFlight = YES;
        self.inFlightMessageId = identifier;
        self.attempts[identifier] = @([self.attempts[identifier] unsignedIntegerValue] + 1);
        NSLog(@"[WcSy] analysis request started");
        self.analysisStatus = @"JEV 正在分析对方消息";
        NSUInteger epoch = ++self.requestEpoch;
        __weak typeof(self) weakSelf = self;
        [self.coordinator analyzeMessageWithId:identifier completion:^(RCMessage *message, RCDecisionResult *decision, NSError *error) {
            RCReplyOverlay *overlay = weakSelf;
            if (!overlay || overlay.requestEpoch != epoch) return;
            // Release the queue even if UIKit temporarily removed our window.
            overlay.analysisInFlight = NO;
            overlay.inFlightMessageId = nil;
            NSLog(@"[WcSy] analysis completed error=%ld visible=%d", (long)error.code, overlay.window != nil);
            if (error || !decision) {
                overlay.analysisStatus = [NSString stringWithFormat:@"JEV 分析失败（错误码 %ld）", (long)error.code];
                [overlay rememberResult:overlay.analysisStatus];
                BOOL retryable = error.code == RCErrorNetwork || error.code == RCErrorTimeout || error.code == RCErrorStaleSession;
                if (retryable && [overlay.attempts[identifier] unsignedIntegerValue] < 2 && overlay.window) {
                    [overlay.processedMessageIds removeObject:identifier];
                    [overlay.pendingMessageIds addObject:identifier];
                    overlay.pendingSince[identifier] = NSDate.date;
                    overlay.lastAnalysisAt = NSDate.date.timeIntervalSince1970 + 3;
                    overlay.analysisStatus = @"暂时失败，稍后重试一次";
                }
                return;
            }
            if (!overlay.window) { overlay.analysisStatus = @"页面暂不可见，队列已恢复"; [overlay rememberResult:overlay.analysisStatus]; return; }
            if (![message.localId isEqualToString:identifier] ||
                ![message.direction isEqualToString:@"incoming"] ||
                RCMessageRenderDirection(identifier) != 1) {
                overlay.analysisStatus = @"消息方向或会话已变化，结果已丢弃";
                [overlay rememberResult:overlay.analysisStatus];
                return;
            }
            overlay.latestDecisionMessageId = identifier;
            BOOL visible = RCRecordInlineDecision(identifier, RCFormatJevAnalysis(decision));
            overlay.analysisStatus = visible ? @"JEV 分析完成，已附在对方消息下方" :
                @"JEV 分析完成，消息滚动回来后显示";
            [overlay rememberResult:overlay.analysisStatus];
        }];
        break;
    }
}
@end

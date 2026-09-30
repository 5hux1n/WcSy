#import "WeChatAdapter.h"
#import "../Core/ContextEngine.h"
#import "../Core/DecisionSchema.h"
#import "../Core/SessionCoordinator.h"
#import "../Overlay/ReplyOverlay.h"
#import "../Overlay/SettingsViewController.h"
#import "../Core/ConversationPolicy.h"
#import "../Core/RemoteGenerationProvider.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <CommonCrypto/CommonDigest.h>

static __weak UIViewController *activePage;
static char pageTokenKey;
static char overlayKey;
static char profileControlKey;
static char chatActionKey;
static char decisionNotesKey;
static char decisionRowsKey;
static char decisionLabelKey;
static char decisionHeightKey;
static char decisionWidthKey;
static char decisionTopKey;
static char decisionLeftKey;
static char decisionBaseHeightsKey;
static char decisionTapTargetKey;
static char decisionUpdatingKey;
static char decisionSequenceKey;
static char decisionLayoutPendingKey;
static char decisionLayoutDirtyKey;
static char observedDirectionsKey;
static char attachedPeerKey;
static NSString *lastChatRuntimeStatus = @"尚未进入聊天页";
static NSString *lastDraftRuntimeStatus = @"尚未尝试填入草稿";
static void RCEnsureChatAction(UIViewController *page, NSString *identifier);

NSString *RCChatRuntimeStatus(void) { return lastChatRuntimeStatus; }
NSString *RCDraftRuntimeStatus(void) { return lastDraftRuntimeStatus; }

static BOOL MethodMatches(Class cls, NSString *name, const char *encoding) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

BOOL RCStaticCompatibilityCheck(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    if (![bundle.bundleIdentifier isEqualToString:@"com.tencent.xin"] ||
        ![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"8.0.78"]) return NO;
    Class page = objc_getClass("BaseMsgContentViewController");
    Class wrap = objc_getClass("CMessageWrap");
    if (!page || !wrap) return NO;
    return MethodMatches(page, @"viewDidAppear:", "v20@0:8B16") &&
        MethodMatches(page, @"viewDidDisappear:", "v20@0:8B16") &&
        MethodMatches(page, @"viewDidLayoutSubviews", "v16@0:8") &&
        MethodMatches(page, @"getChatUserName", "@16@0:8") &&
        MethodMatches(page, @"GetMessagesWrapArray", "@16@0:8") &&
        MethodMatches(wrap, @"m_uiMesLocalID", "I16@0:8") &&
        MethodMatches(wrap, @"m_nsContent", "@16@0:8") &&
        MethodMatches(wrap, @"m_nsFromUsr", "@16@0:8") &&
        MethodMatches(wrap, @"m_uiMessageType", "I16@0:8") &&
        MethodMatches(wrap, @"m_uiCreateTime", "I16@0:8");
}

BOOL RCGroupCompatibilityCheck(void) {
    if (!RCStaticCompatibilityCheck()) return NO;
    Class wrap = objc_getClass("CMessageWrap");
    return MethodMatches(wrap, @"m_nsRealChatUsr", "@16@0:8") &&
        MethodMatches(wrap, @"getSenderUserName", "@16@0:8");
}

BOOL RCInlineCompatibilityCheck(void) {
    if (!RCStaticCompatibilityCheck()) return NO;
    Class page = objc_getClass("BaseMsgContentViewController");
    return MethodMatches(page, @"getMsgTableView", "@16@0:8") &&
        MethodMatches(page, @"getChatTableViewCellWithMsg:", "@24@0:8@16") &&
        MethodMatches(page, @"tableView:heightForRowAtIndexPath:", "d32@0:8@16@24") &&
        MethodMatches(page, @"tableView:cellForRowAtIndexPath:", "@32@0:8@16@24") &&
        objc_getClass("ChatTableViewCell") != Nil;
}

BOOL RCProfileCompatibilityCheck(BOOL group) {
    if (!RCStaticCompatibilityCheck() || (group && !RCGroupCompatibilityCheck())) return NO;
    Class cls = NSClassFromString(group ? @"ChatRoomInfoViewController" : @"ContactInfoViewController");
    Class contact = NSClassFromString(@"CContact");
    NSString *primary = group ? @"m_chatRoomContact" : @"m_contact";
    NSString *fallback = group ? @"getChatContact" : @"m_chatContact";
    return MethodMatches(cls, @"viewDidAppear:", "v20@0:8B16") &&
        (MethodMatches(cls, primary, "@16@0:8") || MethodMatches(cls, fallback, "@16@0:8")) &&
        MethodMatches(contact, @"userName", "@16@0:8");
}

static BOOL RCGetterMatches(id object, SEL selector, char returnType, unsigned int arguments) {
    Method method = object ? class_getInstanceMethod(object_getClass(object), selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == returnType;
}

static id CallObject(id object, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!RCGetterMatches(object, sel, '@', 2)) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, sel); }
    @catch (NSException *exception) { (void)exception; return nil; }
}

static id CallObjectArg(id object, NSString *selector, id argument) {
    SEL sel = NSSelectorFromString(selector);
    if (!RCGetterMatches(object, sel, '@', 3)) return nil;
    char type[64] = {0};
    method_getArgumentType(class_getInstanceMethod(object_getClass(object), sel), 2, type, sizeof(type));
    if (type[0] != '@') return nil;
    @try { return ((id (*)(id, SEL, id))objc_msgSend)(object, sel, argument); }
    @catch (NSException *exception) { (void)exception; return nil; }
}

static unsigned int CallUInt(id object, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!RCGetterMatches(object, sel, 'I', 2)) return 0;
    @try { return ((unsigned int (*)(id, SEL))objc_msgSend)(object, sel); }
    @catch (NSException *exception) { (void)exception; return 0; }
}

// WeChat's rendered bubble model is the direction source for JEV analysis.
static NSMutableDictionary<NSString *, NSNumber *> *RCObservedDirections(UIViewController *page) {
    NSMutableDictionary *directions = objc_getAssociatedObject(page, &observedDirectionsKey);
    if (!directions) {
        directions = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(page, &observedDirectionsKey, directions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return directions;
}

static NSNumber *RCDirectionFromCell(UITableViewCell *cell, unsigned int expectedId) {
    if (!expectedId || ![cell isKindOfClass:NSClassFromString(@"ChatTableViewCell")]) return nil;
    id model = CallObject(CallObject(cell, @"cellView"), @"viewModel");
    id wrap = CallObject(model, @"messageWrap");
    if (!wrap || CallUInt(wrap, @"m_uiMesLocalID") != expectedId) return nil;
    SEL selector = NSSelectorFromString(@"isSender");
    if (!RCGetterMatches(model, selector, 'B', 2) && !RCGetterMatches(model, selector, 'c', 2)) return nil;
    @try { return @(!((BOOL (*)(id, SEL))objc_msgSend)(model, selector)); }
    @catch (NSException *exception) { (void)exception; return nil; }
}

void RCObserveRenderedCell(UIViewController *page, UITableView *tableView, UITableViewCell *cell) {
    if (page != activePage || tableView != CallObject(page, @"getMsgTableView")) return;
    id model = CallObject(CallObject(cell, @"cellView"), @"viewModel");
    id wrap = CallObject(model, @"messageWrap");
    unsigned int identifier = CallUInt(wrap, @"m_uiMesLocalID");
    NSNumber *incoming = RCDirectionFromCell(cell, identifier);
    if (incoming) RCObservedDirections(page)[[@(identifier) stringValue]] = incoming;
}

NSInteger RCMessageRenderDirection(NSString *messageId) {
    UIViewController *page = activePage;
    if (!page || !messageId.length || [messageId hasPrefix:@"observed-"]) return -1;
    NSNumber *known = RCObservedDirections(page)[messageId];
    if (known) return known.boolValue ? 1 : 0;
    UITableView *table = CallObject(page, @"getMsgTableView");
    if ([table isKindOfClass:UITableView.class]) {
        for (UITableViewCell *cell in table.visibleCells) RCObserveRenderedCell(page, table, cell);
        known = RCObservedDirections(page)[messageId];
        if (known) return known.boolValue ? 1 : 0;
    }
    NSArray *wraps = CallObject(page, @"GetMessagesWrapArray");
    for (id wrap in wraps) {
        unsigned int identifier = CallUInt(wrap, @"m_uiMesLocalID");
        if (![[@(identifier) stringValue] isEqualToString:messageId]) continue;
        UITableViewCell *cell = CallObjectArg(page, @"getChatTableViewCellWithMsg:", wrap);
        known = RCDirectionFromCell(cell, identifier);
        if (known) {
            RCObservedDirections(page)[messageId] = known;
            return known.boolValue ? 1 : 0;
        }
        break;
    }
    return -1;
}

@interface RCWeChatAdapter ()
@property (nonatomic, readwrite) BOOL supported;
@property (nonatomic, copy, readwrite) NSString *version;
@end

@implementation RCWeChatAdapter
- (instancetype)initWithVersion:(NSString *)version build:(NSString *)build {
    if ((self = [super init])) {
        _version = [version copy];
        (void)build;
        _supported = [version isEqualToString:@"8.0.78"] && RCStaticCompatibilityCheck();
    }
    return self;
}

- (RCSessionHandle *)currentSession {
    UIViewController *page = activePage;
    if (!self.supported || !page || !page.view.window) return nil;
    NSString *peer = CallObject(page, @"getChatUserName");
    if (![peer isKindOfClass:NSString.class] || !peer.length) return nil;
    if ([peer hasSuffix:@"@chatroom"] && !RCGroupCompatibilityCheck()) return nil;
    NSString *token = objc_getAssociatedObject(page, &pageTokenKey);
    if (!token.length) return nil;
    RCSessionHandle *handle = [RCSessionHandle new];
    handle.sessionId = peer;
    handle.pageToken = token;
    return handle;
}

- (NSArray<RCMessage *> *)recentMessagesForSession:(RCSessionHandle *)session
                                               limit:(NSUInteger)limit error:(NSError **)error {
    RCSessionHandle *current = [self currentSession];
    if (!current || ![current.sessionId isEqualToString:session.sessionId] ||
        ![current.pageToken isEqualToString:session.pageToken]) {
        if (error) *error = RCError(RCErrorStaleSession);
        return nil;
    }
    id raw = CallObject(activePage, @"GetMessagesWrapArray");
    if (![raw isKindOfClass:NSArray.class]) {
        if (error) *error = RCError(RCErrorUnsupportedVersion);
        return nil;
    }
    NSArray *array = raw;
    NSUInteger count = MIN(limit, 100);
    NSUInteger start = array.count > count ? array.count - count : 0;
    NSMutableArray<RCMessage *> *result = [NSMutableArray array];
    Class wrapClass = objc_getClass("CMessageWrap");
    // Historical group rows may be offscreen. Infer their role only after a
    // rendered outgoing row has established this account's sender identifier.
    NSString *confirmedSelf = nil;
    if ([session.sessionId hasSuffix:@"@chatroom"]) {
        for (id wrap in array) {
            NSNumber *direction = RCObservedDirections(activePage)[[@(CallUInt(wrap, @"m_uiMesLocalID")) stringValue]];
            if (!direction || direction.boolValue) continue;
            id sender = CallObject(wrap, @"m_nsFromUsr");
            if ([sender isKindOfClass:NSString.class] && [sender length] && ![sender hasSuffix:@"@chatroom"]) {
                confirmedSelf = sender;
                break;
            }
        }
    }
    for (NSUInteger i = start; i < array.count; i++) {
        id wrap = array[i];
        if (![wrap isKindOfClass:wrapClass]) {
            RCMessage *unknown = [RCMessage new];
            unknown.localId = [NSString stringWithFormat:@"observed-%lu", (unsigned long)i];
            unknown.senderId = @"unknown";
            unknown.direction = @"unknown";
            unknown.kind = @"other";
            unknown.text = @"[消息内容暂不可读]";
            unknown.partial = YES;
            [result addObject:unknown];
            continue;
        }
        NSString *sender = CallObject(wrap, @"m_nsFromUsr");
        NSString *content = CallObject(wrap, @"m_nsContent");
        unsigned int type = CallUInt(wrap, @"m_uiMessageType");
        BOOL incomplete = ![sender isKindOfClass:NSString.class] ||
            (type == 1 && ![content isKindOfClass:NSString.class]);
        if (![sender isKindOfClass:NSString.class]) sender = @"";
        if (![content isKindOfClass:NSString.class]) content = @"";
        unsigned int identifier = CallUInt(wrap, @"m_uiMesLocalID");
        RCMessage *message = [RCMessage new];
        message.localId = identifier ? [@(identifier) stringValue] : [NSString stringWithFormat:@"observed-%lu", (unsigned long)i];
        NSNumber *rendered = identifier ? RCObservedDirections(activePage)[message.localId] : nil;
        NSInteger renderedDirection = rendered ? (rendered.boolValue ? 1 : 0) : -1;
        if ([session.sessionId hasSuffix:@"@chatroom"]) {
            NSString *member = CallObject(wrap, @"m_nsRealChatUsr");
            if (![member isKindOfClass:NSString.class] || !member.length) member = CallObject(wrap, @"getSenderUserName");
            if ([member isKindOfClass:NSString.class] && [member hasSuffix:@"@chatroom"]) member = nil;
            if (renderedDirection < 0 && confirmedSelf.length) {
                if ([sender isEqualToString:confirmedSelf] || [member isEqualToString:confirmedSelf]) renderedDirection = 0;
                else if ([member isKindOfClass:NSString.class] && member.length) renderedDirection = 1;
            }
            message.direction = renderedDirection >= 0 ? (renderedDirection ? @"incoming" : @"outgoing") : @"unknown";
            message.partial = renderedDirection < 0 || ![member isKindOfClass:NSString.class] || !member.length;
            message.senderId = [message.direction isEqualToString:@"outgoing"] ? @"self" :
                ([member isKindOfClass:NSString.class] && member.length ? member : @"unknown");
        } else {
            message.direction = renderedDirection >= 0 ? (renderedDirection ? @"incoming" : @"outgoing") :
                (sender.length ? ([sender isEqualToString:session.sessionId] ? @"incoming" : @"outgoing") : @"unknown");
            message.senderId = sender;
        }
        message.kind = type == 1 ? @"text" : @"other";
        message.partial |= incomplete || type != 1;
        message.text = type == 1 ? content : @"[非文字消息，内容未读取]";
        message.timestampMs = (long long)CallUInt(wrap, @"m_uiCreateTime") * 1000;
        [result addObject:message];
    }
    return result;
}

- (id)inputToolForSession:(RCSessionHandle *)session error:(NSError **)error {
    RCSessionHandle *current = [self currentSession];
    if (!current || ![current.sessionId isEqualToString:session.sessionId] ||
        ![current.pageToken isEqualToString:session.pageToken]) {
        lastDraftRuntimeStatus = @"会话已变化";
        if (error) *error = RCError(RCErrorStaleSession);
        return nil;
    }
    id tool = CallObject(activePage, @"getInputToolView");
    if (!tool || ![tool isKindOfClass:objc_getClass("MMInputToolView")]) {
        lastDraftRuntimeStatus = @"微信输入工具未定位";
        if (error) *error = RCError(RCErrorInputUnavailable);
        return nil;
    }
    return tool;
}

- (NSString *)draftForSession:(RCSessionHandle *)session error:(NSError **)error {
    id tool = [self inputToolForSession:session error:error];
    if (!tool) return nil;
    id draft = CallObject(tool, @"GetCurrentText");
    if (![draft isKindOfClass:NSString.class]) {
        lastDraftRuntimeStatus = @"微信当前草稿读取失败";
        if (error) *error = RCError(RCErrorInputUnavailable);
        return nil;
    }
    return draft;
}

- (BOOL)fillDraft:(NSString *)text session:(RCSessionHandle *)session
     expectedHash:(NSString *)snapshotHash allowOverwrite:(BOOL)allowOverwrite error:(NSError **)error {
    lastDraftRuntimeStatus = @"正在核对会话与输入框";
    NSArray<RCMessage *> *messages = [self recentMessagesForSession:session limit:20 error:error];
    if (!messages) { lastDraftRuntimeStatus = @"当前消息读取失败"; return NO; }
    RCContextSnapshot *fresh = [RCContextEngine buildWithMessages:messages session:session
        requestId:@"fill" limit:20 maxCharacters:4000];
    if (![fresh.snapshotHash isEqualToString:snapshotHash]) {
        lastDraftRuntimeStatus = @"消息快照已变化";
        if (error) *error = RCError(RCErrorStaleSession);
        return NO;
    }
    id tool = [self inputToolForSession:session error:error];
    if (!tool) return NO;
    NSString *before = [self draftForSession:session error:error];
    if (!before) return NO;
    if (before.length && !allowOverwrite) {
        lastDraftRuntimeStatus = @"已有草稿，等待覆盖确认";
        if (error) *error = RCError(RCErrorDraftPresent);
        return NO;
    }
    SEL setter = NSSelectorFromString(@"setText:");
    id grow = nil;
    UITextView *editor = nil;
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(tool, setter, text);
        NSString *after = [self draftForSession:session error:error];
        if ([after isEqualToString:text]) { lastDraftRuntimeStatus = @"输入工具写入并读回成功"; return YES; }
        lastDraftRuntimeStatus = @"输入工具写入后读回不一致";
        // 8.0.78 exposes a separate growing text editor. The tool setter may
        // update its model without changing the visible composer.
        grow = CallObject(tool, @"getGrowTextView");
        if (grow && [grow respondsToSelector:setter]) {
            ((void (*)(id, SEL, id))objc_msgSend)(grow, setter, text);
            after = [self draftForSession:session error:error];
            if ([after isEqualToString:text]) { lastDraftRuntimeStatus = @"增长文本控件写入并读回成功"; return YES; }
            lastDraftRuntimeStatus = @"增长文本控件写入后读回不一致";
        }
        id textArea = CallObject(grow, @"textArea");
        if ([textArea isKindOfClass:UITextView.class]) {
            editor = textArea;
            editor.text = text;
            [NSNotificationCenter.defaultCenter postNotificationName:UITextViewTextDidChangeNotification object:editor];
            after = [self draftForSession:session error:error];
            if ([after isEqualToString:text]) { lastDraftRuntimeStatus = @"文本编辑区写入并读回成功"; return YES; }
            lastDraftRuntimeStatus = @"文本编辑区写入后读回不一致";
            editor.text = before;
            [NSNotificationCenter.defaultCenter postNotificationName:UITextViewTextDidChangeNotification object:editor];
        }
        ((void (*)(id, SEL, id))objc_msgSend)(tool, setter, before);
        if (grow && [grow respondsToSelector:setter])
            ((void (*)(id, SEL, id))objc_msgSend)(grow, setter, before);
    } @catch (NSException *exception) {
        (void)exception;
        lastDraftRuntimeStatus = @"微信输入控件抛出异常";
        @try {
            if (editor) editor.text = before;
            if (grow && [grow respondsToSelector:setter])
                ((void (*)(id, SEL, id))objc_msgSend)(grow, setter, before);
            ((void (*)(id, SEL, id))objc_msgSend)(tool, setter, before);
        } @catch (NSException *rollbackException) { (void)rollbackException; }
    }
    if (error) *error = RCError(RCErrorInputUnavailable);
    return NO;
}
@end

void RCPageAppeared(UIViewController *page) {
    if (!NSThread.isMainThread || !page.isViewLoaded || !page.view.window) {
        lastChatRuntimeStatus = @"聊天页面尚未显示";
        return;
    }
    RCReplyOverlay *existing = objc_getAssociatedObject(page, &overlayKey);
    if (page.navigationController && page.navigationController.topViewController != page) {
        lastChatRuntimeStatus = @"当前页面不是聊天页顶部";
        return;
    }
    if (!RCStaticCompatibilityCheck()) { lastChatRuntimeStatus = @"聊天接口检查未通过"; return; }
    id peer = CallObject(page, @"getChatUserName");
    if (![peer isKindOfClass:NSString.class] || ![peer length]) {
        lastChatRuntimeStatus = @"当前会话标识暂不可用";
        return;
    }
    NSString *attachedPeer = objc_getAssociatedObject(page, &attachedPeerKey);
    if (existing && attachedPeer.length && ![attachedPeer isEqualToString:peer]) {
        RCPageDisappeared(page);
        existing = nil;
    }
    RCEnsureChatAction(page, peer);
    if (!RCSettingsEnabled()) {
        lastChatRuntimeStatus = @"全局插件未启用";
        if (existing) RCPageDisappeared(page);
        return;
    }
    if (!RCConversationEnabled(peer)) {
        if (existing) RCPageDisappeared(page);
        lastChatRuntimeStatus = @"此聊天的咨询开关未命中";
        return;
    }
    if ([peer hasSuffix:@"@chatroom"] && !RCGroupCompatibilityCheck()) {
        if (existing) RCPageDisappeared(page);
        lastChatRuntimeStatus = @"群消息接口检查未通过";
        return;
    }
    if (!RCInlineCompatibilityCheck()) {
        if (existing) RCPageDisappeared(page);
        lastChatRuntimeStatus = @"消息行引用接口检查未通过";
        return;
    }
    if (existing && existing.superview) { lastChatRuntimeStatus = @"已附着聊天页"; return; }
    if (existing) RCPageDisappeared(page);
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    RCWeChatAdapter *adapter = [[RCWeChatAdapter alloc] initWithVersion:version build:build];
    if (!adapter.supported) { lastChatRuntimeStatus = @"微信版本未适配"; return; }
    if (activePage && activePage != page) RCPageDisappeared(activePage);
    activePage = page;
    objc_setAssociatedObject(page, &attachedPeerKey, peer, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(page, &pageTokenKey, NSUUID.UUID.UUIDString, OBJC_ASSOCIATION_COPY_NONATOMIC);
    RCSessionCoordinator *coordinator = [[RCSessionCoordinator alloc] initWithAdapter:adapter];
    RCReplyOverlay *overlay = [[RCReplyOverlay alloc] initWithCoordinator:coordinator];
    objc_setAssociatedObject(page, &overlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [overlay attachToChatView:page.view];
    RCRefreshInlineDecisions(nil);
    lastChatRuntimeStatus = @"已附着聊天页";
}

void RCConversationPolicyChanged(NSString *identifier) {
    if (!NSThread.isMainThread || ![identifier isKindOfClass:NSString.class]) return;
    UIViewController *page = activePage;
    if (!page) return;
    NSString *current = CallObject(page, @"getChatUserName");
    if ([current isEqualToString:identifier] && !RCConversationEnabled(identifier)) {
        RCPageDisappeared(page);
        lastChatRuntimeStatus = @"此聊天的咨询开关已关闭";
    }
}

@interface RCChatAction : NSObject
@property (nonatomic, weak) UIViewController *page;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) UIBarButtonItem *item;
@property (nonatomic, strong) NSTimer *statusTimer;
- (void)open;
@end

@implementation RCChatAction
- (void)open {
    UIViewController *page = self.page;
    if (!page || !page.view.window || page.presentedViewController) return;
    if (RCConversationEnabled(self.identifier)) {
        RCReplyOverlay *overlay = objc_getAssociatedObject(page, &overlayKey);
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"此聊天的决策咨询已开启"
            message:overlay ? [overlay statusSummary] : [NSString stringWithFormat:@"当前：%@", RCChatRuntimeStatus()]
            preferredStyle:UIAlertControllerStyleActionSheet];
        UIAlertAction *retry = [UIAlertAction actionWithTitle:@"重新分析最近的对方消息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                RCReplyOverlay *overlay = objc_getAssociatedObject(page, &overlayKey);
                [overlay reanalyzeLatestIncoming];
            });
        }];
        retry.enabled = overlay && !overlay.isAnalyzing;
        [sheet addAction:retry];
        [sheet addAction:[UIAlertAction actionWithTitle:@"关闭此聊天" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            (void)action;
            RCSetConversationEnabled(self.identifier, NO);
            self.item.title = @"咨询";
            RCPageDisappeared(page);
            lastChatRuntimeStatus = @"此聊天的咨询开关已关闭";
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.barButtonItem = self.item;
        [page presentViewController:sheet animated:YES completion:nil];
        [self.statusTimer invalidate];
        __weak UIViewController *weakPage = page;
        __weak UIAlertController *weakSheet = sheet;
        __weak UIAlertAction *weakRetry = retry;
        self.statusTimer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            UIAlertController *currentSheet = weakSheet;
            UIViewController *currentPage = weakPage;
            if (!currentSheet || !currentPage.view.window || currentSheet.isBeingDismissed ||
                currentPage.presentedViewController != currentSheet) {
                [timer invalidate];
                return;
            }
            RCReplyOverlay *current = objc_getAssociatedObject(currentPage, &overlayKey);
            NSString *summary = current ? [current statusSummary] :
                [NSString stringWithFormat:@"当前：%@", RCChatRuntimeStatus()];
            if (![currentSheet.message isEqualToString:summary]) currentSheet.message = summary;
            weakRetry.enabled = current && !current.isAnalyzing;
        }];
        [NSRunLoop.mainRunLoop addTimer:self.statusTimer forMode:NSRunLoopCommonModes];
        return;
    }
    if (!RCSettingsEnabled() || !RCLoadJevAPIKey().length) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"先配置 JEV 密钥"
            message:@"请在 WcSy 设置中保存 JEV API Key，并启用插件。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [page presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开启此聊天的决策咨询？"
        message:@"当前打开此聊天时，新收到的文字消息及最多 100 条已加载对话（总计最多约 16000 字符）会发送给 JEV（api.typesafe.ai）分析。结果只在本机显示，不会作为微信消息发送。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"允许并开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        RCSetConversationEnabled(self.identifier, YES);
        self.item.title = @"咨询 ✓";
        RCPageAppeared(page);
    }]];
    [page presentViewController:alert animated:YES completion:nil];
}
@end

static void RCEnsureChatAction(UIViewController *page, NSString *identifier) {
    RCChatAction *action = objc_getAssociatedObject(page, &chatActionKey);
    if (!action) {
        action = [RCChatAction new];
        action.page = page;
        action.item = [[UIBarButtonItem alloc] initWithTitle:@"咨询"
            style:UIBarButtonItemStylePlain target:action action:@selector(open)];
        action.item.accessibilityLabel = @"此聊天的决策咨询";
        objc_setAssociatedObject(page, &chatActionKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    action.identifier = identifier;
    action.item.title = RCConversationEnabled(identifier) ? @"咨询 ✓" : @"咨询";
    if (![page.navigationItem.rightBarButtonItems containsObject:action.item]) {
        NSArray *items = page.navigationItem.rightBarButtonItems ?: @[];
        page.navigationItem.rightBarButtonItems = [items arrayByAddingObject:action.item];
    }
}

void RCPageDisappeared(UIViewController *page) {
    UITableView *table = CallObject(page, @"getMsgTableView");
    if ([table isKindOfClass:UITableView.class]) {
        for (UITableViewCell *cell in table.visibleCells)
            ((UILabel *)objc_getAssociatedObject(cell, &decisionLabelKey)).hidden = YES;
    }
    RCReplyOverlay *overlay = objc_getAssociatedObject(page, &overlayKey);
    [overlay detach];
    objc_setAssociatedObject(page, &overlayKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &pageTokenKey, nil, OBJC_ASSOCIATION_ASSIGN);
    if (activePage == page) activePage = nil;
    objc_setAssociatedObject(page, &decisionNotesKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &decisionRowsKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &decisionBaseHeightsKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &decisionSequenceKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &decisionLayoutPendingKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &decisionLayoutDirtyKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &observedDirectionsKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(page, &attachedPeerKey, nil, OBJC_ASSOCIATION_ASSIGN);
    // Closing the switch can detach while this page is still visible.
    if ([table isKindOfClass:UITableView.class] && page.view.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (activePage == page || !table.window || table.hasUncommittedUpdates || table.tracking) return;
            [UIView performWithoutAnimation:^{ [table beginUpdates]; [table endUpdates]; }];
        });
    }
}

static NSString *RCDecisionStorePath(UIViewController *page) {
    NSString *peer = objc_getAssociatedObject(page, &attachedPeerKey);
    if (![peer isKindOfClass:NSString.class] || !peer.length) return nil;
    NSData *data = [peer dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    if (!support.length) return nil;
    return [[support stringByAppendingPathComponent:@"WcSy/Decisions"]
        stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
}

static NSMutableDictionary<NSString *, NSString *> *RCLoadStoredNotes(UIViewController *page) {
    NSMutableDictionary<NSString *, NSString *> *notes = [NSMutableDictionary dictionary];
    NSString *path = RCDecisionStorePath(page);
    if (!path.length) return notes;
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:path];
    NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - 30 * 24 * 60 * 60;
    for (id identifier in stored) {
        id entry = stored[identifier];
        if (![identifier isKindOfClass:NSString.class] || ![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *value = entry[@"text"];
        NSNumber *created = entry[@"at"];
        if ([value isKindOfClass:NSString.class] && value.length &&
            [created isKindOfClass:NSNumber.class] && created.doubleValue >= cutoff)
            notes[identifier] = value;
    }
    return notes;
}

static NSMutableDictionary<NSString *, NSString *> *RCNotes(UIViewController *page) {
    NSMutableDictionary *notes = objc_getAssociatedObject(page, &decisionNotesKey);
    if (!notes) {
        notes = RCLoadStoredNotes(page);
        objc_setAssociatedObject(page, &decisionNotesKey, notes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return notes;
}

static void RCStoreNote(UIViewController *page, NSString *identifier, NSString *text) {
    NSString *path = RCDecisionStorePath(page);
    if (!path.length) { NSLog(@"[WcSy] decision-store failed: no session path"); return; }
    NSMutableDictionary *stored = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - 30 * 24 * 60 * 60;
    for (id key in [stored.allKeys copy]) {
        id entry = stored[key];
        NSNumber *created = [entry isKindOfClass:NSDictionary.class] ? entry[@"at"] : nil;
        if (![created isKindOfClass:NSNumber.class] || created.doubleValue < cutoff) [stored removeObjectForKey:key];
    }
    stored[identifier] = @{ @"text": text, @"at": @(NSDate.date.timeIntervalSince1970) };
    while (stored.count > 50) {
        NSString *oldest = [stored.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [stored[a][@"at"] compare:stored[b][@"at"]];
        }].firstObject;
        if (!oldest) break;
        [stored removeObjectForKey:oldest];
    }
    NSString *directory = path.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
        attributes:@{ NSFileProtectionKey: NSFileProtectionComplete } error:nil];
    if ([stored writeToFile:path atomically:YES]) {
        [NSFileManager.defaultManager setAttributes:@{ NSFileProtectionKey: NSFileProtectionComplete }
            ofItemAtPath:path error:nil];
        [[NSURL fileURLWithPath:path] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    } else NSLog(@"[WcSy] decision-store failed: atomic write (no message content logged)");
}

static NSDictionary<NSIndexPath *, NSString *> *RCRows(UIViewController *page) {
    return objc_getAssociatedObject(page, &decisionRowsKey) ?: @{};
}

// Append-only arrivals preserve existing row identities. History insertion,
// deletion or reordering invalidates them, even if the message count is unchanged.
static void RCSyncRowSequence(UIViewController *page) {
    NSArray *wraps = CallObject(page, @"GetMessagesWrapArray");
    if (![wraps isKindOfClass:NSArray.class]) return;
    NSMutableArray *sequence = [NSMutableArray arrayWithCapacity:wraps.count];
    for (id wrap in wraps) [sequence addObject:[NSString stringWithFormat:@"%u:%u",
        CallUInt(wrap, @"m_uiMesLocalID"), CallUInt(wrap, @"m_uiCreateTime")]];
    NSArray *previous = objc_getAssociatedObject(page, &decisionSequenceKey);
    if ([previous isEqualToArray:sequence]) return;
    BOOL appended = previous && previous.count <= sequence.count &&
        [[sequence subarrayWithRange:NSMakeRange(0, previous.count)] isEqualToArray:previous];
    if (!appended && RCRows(page).count) {
        objc_setAssociatedObject(page, &decisionRowsKey, @{}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(page, &decisionBaseHeightsKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(page, &decisionLayoutDirtyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(page, &decisionSequenceKey, [sequence copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void RCScheduleInlineLayout(UIViewController *page, UITableView *table) {
    if (!objc_getAssociatedObject(page, &decisionLayoutDirtyKey) ||
        objc_getAssociatedObject(page, &decisionLayoutPendingKey) ||
        objc_getAssociatedObject(page, &decisionUpdatingKey)) return;
    NSString *token = [objc_getAssociatedObject(page, &pageTokenKey) copy];
    objc_setAssociatedObject(page, &decisionLayoutPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIViewController *weakPage = page;
    __weak UITableView *weakTable = table;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *current = weakPage;
        UITableView *view = weakTable;
        if (!current || current != activePage ||
            ![token isEqualToString:objc_getAssociatedObject(current, &pageTokenKey)]) return;
        objc_setAssociatedObject(current, &decisionLayoutPendingKey, nil, OBJC_ASSOCIATION_ASSIGN);
        // Timer retries once UIKit finishes its own updates or the user stops scrolling.
        if (!view.window || view.tracking || view.dragging || view.decelerating || view.hasUncommittedUpdates ||
            objc_getAssociatedObject(current, &decisionUpdatingKey)) return;
        objc_setAssociatedObject(current, &decisionLayoutDirtyKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(current, &decisionUpdatingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try {
            [UIView performWithoutAnimation:^{
                [view beginUpdates];
                [view endUpdates];
                [view layoutIfNeeded];
            }];
            for (UITableViewCell *cell in view.visibleCells)
                RCConfigureInlineCell(current, view, cell, [view indexPathForCell:cell]);
        } @finally {
            objc_setAssociatedObject(current, &decisionUpdatingKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    });
}

static UIColor *nativeReferenceBackgroundColor;
static UIColor *nativeReferenceTextColor;
static UIFont *nativeReferenceFont;
static CGFloat nativeReferenceCornerRadius;

// Sample only views WeChat has already created. Never initialize private UI
// classes just to query their defaults, and never move or modify a native view.
static void RCSampleReferenceTree(UIView *view, NSUInteger depth, NSUInteger *budget, BOOL insideReference) {
    if (!view || !*budget || depth > 10) return;
    (*budget)--;
    NSString *name = NSStringFromClass(view.class);
    BOOL reference = insideReference || [name containsString:@"Refer"] || [name containsString:@"Quote"];
    if (reference) {
        id container = CallObject(view, @"containerView");
        UIColor *color = [container isKindOfClass:UIView.class] ? ((UIView *)container).backgroundColor : view.backgroundColor;
        if (color && CGColorGetAlpha(color.CGColor) > 0.1) nativeReferenceBackgroundColor = color;
        CGFloat radius = [container isKindOfClass:UIView.class] ? ((UIView *)container).layer.cornerRadius : view.layer.cornerRadius;
        if (radius > 0 && radius <= 20) nativeReferenceCornerRadius = radius;
        id font = CallObject(view, @"font");
        id textColor = CallObject(view, @"textColor");
        if ([font isKindOfClass:UIFont.class] && [font pointSize] >= 9 && [font pointSize] <= 18)
            nativeReferenceFont = font;
        if ([textColor isKindOfClass:UIColor.class]) nativeReferenceTextColor = textColor;
    }
    for (UIView *child in view.subviews) RCSampleReferenceTree(child, depth + 1, budget, reference);
}

NSString *RCNativeReferenceStyleStatus(void) {
    return [NSString stringWithFormat:@"背景%@ / 字体%@ / 圆角%@",
        nativeReferenceBackgroundColor ? @"微信引用" : @"系统备用",
        nativeReferenceFont ? @"微信引用" : @"系统备用",
        nativeReferenceCornerRadius > 0 ? @"微信引用" : @"默认"];
}

static NSString *RCDecisionPreview(NSString *text) { return RCJevAnalysisPreview(text); }

static UIFont *RCDecisionPreviewFont(void) {
    return nativeReferenceFont && nativeReferenceFont.pointSize <= 14 ? nativeReferenceFont :
        [UIFont systemFontOfSize:12];
}

static CGFloat RCInlineNoteWidth(UITableView *tableView, NSString *text) {
    CGFloat maximum = MAX(130, CGRectGetWidth(tableView.bounds) - 92);
    CGFloat natural = [RCDecisionPreview(text) sizeWithAttributes:@{
        NSFontAttributeName: RCDecisionPreviewFont() }].width + 24;
    return ceil(MIN(maximum, MAX(100, natural)));
}

static CGFloat RCInlineNoteHeight(UITableView *tableView, NSString *text) {
    (void)tableView;
    if (!text.length) return 0;
    return ceil(MAX(28, RCDecisionPreviewFont().lineHeight + 12));
}

@interface RCDecisionTapTarget : NSObject
@property (nonatomic, weak) UIViewController *page;
@property (nonatomic, copy) NSString *messageId;
- (void)open:(UITapGestureRecognizer *)recognizer;
@end

@implementation RCDecisionTapTarget
- (void)open:(UITapGestureRecognizer *)recognizer {
    (void)recognizer;
    UIViewController *page = self.page;
    NSString *decision = page ? RCNotes(page)[self.messageId] : nil;
    if (page != activePage || !page.view.window || page.presentedViewController || !decision.length) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"决策咨询"
        message:RCDisplayStoredAnalysis(decision) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
    [page presentViewController:alert animated:YES completion:nil];
}
@end

CGFloat RCInlineExtraHeight(UIViewController *page, UITableView *tableView, NSIndexPath *indexPath, CGFloat originalHeight) {
    if (page != activePage || tableView != CallObject(page, @"getMsgTableView") || !indexPath) return 0;
    RCSyncRowSequence(page);
    NSMutableDictionary *heights = objc_getAssociatedObject(page, &decisionBaseHeightsKey);
    if (!heights) {
        heights = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(page, &decisionBaseHeightsKey, heights, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    heights[indexPath] = @(originalHeight);
    NSString *messageId = RCRows(page)[indexPath];
    NSString *note = messageId ? RCNotes(page)[messageId] : nil;
    return note.length ? RCInlineNoteHeight(tableView, note) + 4 : 0;
}

// Measure the native message content, excluding our sibling label and the
// avatar column. The quote sits 2 pt below content rather than at the row bottom.
static void RCMeasureNativeContent(UIView *view, UIView *content, NSUInteger depth,
                                   NSUInteger *budget, CGRect *result) {
    if (!view || view.hidden || view.alpha < 0.01 || !*budget || depth > 10) return;
    (*budget)--;
    NSString *name = NSStringFromClass(view.class);
    BOOL leaf = [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] ||
        [view isKindOfClass:UITextView.class] || [name containsString:@"RichText"] || [name containsString:@"Bubble"];
    if (leaf && ![name containsString:@"Time"] && ![name containsString:@"Avatar"]) {
        CGRect frame = [view convertRect:view.bounds toView:content];
        if (CGRectGetMinX(frame) >= 40 && CGRectGetWidth(frame) >= 12 && CGRectGetHeight(frame) >= 8 &&
            CGRectGetMaxX(frame) <= CGRectGetWidth(content.bounds) - 4 &&
            CGRectGetMaxY(frame) <= CGRectGetHeight(content.bounds) && CGRectGetMinY(frame) >= 0)
            *result = CGRectIsNull(*result) ? frame : CGRectUnion(*result, frame);
    }
    for (UIView *child in view.subviews) RCMeasureNativeContent(child, content, depth + 1, budget, result);
}

void RCConfigureInlineCell(UIViewController *page, UITableView *tableView, UITableViewCell *cell, NSIndexPath *indexPath) {
    if (![cell isKindOfClass:UITableViewCell.class]) return;
    if (page != activePage || tableView != CallObject(page, @"getMsgTableView") || !indexPath) {
        ((UILabel *)objc_getAssociatedObject(cell, &decisionLabelKey)).hidden = YES;
        return;
    }
    RCSyncRowSequence(page);
    RCObserveRenderedCell(page, tableView, cell);
    NSUInteger budget = 150;
    RCSampleReferenceTree(cell.contentView, 0, &budget, NO);
    id model = CallObject(CallObject(cell, @"cellView"), @"viewModel");
    id wrap = CallObject(model, @"messageWrap");
    unsigned int localId = CallUInt(wrap, @"m_uiMesLocalID");
    // A partially configured cell must not erase an existing row's height.
    if (!localId) {
        ((UILabel *)objc_getAssociatedObject(cell, &decisionLabelKey)).hidden = YES;
        return;
    }
    NSString *renderedId = [@(localId) stringValue];
    NSNumber *incoming = RCDirectionFromCell(cell, localId);
    NSString *desired = incoming.boolValue && CallUInt(wrap, @"m_uiMessageType") == 1 &&
        RCNotes(page)[renderedId] ? renderedId : nil;
    NSString *previousId = RCRows(page)[indexPath];
    if (incoming && !((!desired && !previousId) || [desired isEqualToString:previousId])) {
        NSMutableDictionary *rows = [RCRows(page) mutableCopy];
        if (desired) rows[indexPath] = desired;
        else [rows removeObjectForKey:indexPath];
        objc_setAssociatedObject(page, &decisionRowsKey, [rows copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(page, &decisionLayoutDirtyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    RCScheduleInlineLayout(page, tableView);
    if (!incoming || !incoming.boolValue) {
        ((UILabel *)objc_getAssociatedObject(cell, &decisionLabelKey)).hidden = YES;
        return;
    }
    NSString *messageId = RCRows(page)[indexPath];
    UILabel *label = objc_getAssociatedObject(cell, &decisionLabelKey);
    if (!messageId) { label.hidden = YES; return; }
    NSString *text = RCNotes(page)[messageId];
    if (!text.length) { label.hidden = YES; return; }
    if (!label) {
        label = [UILabel new];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = RCDecisionPreviewFont();
        label.adjustsFontForContentSizeCategory = YES;
        label.numberOfLines = 1;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.textColor = nativeReferenceTextColor ?: UIColor.secondaryLabelColor;
        label.backgroundColor = nativeReferenceBackgroundColor ?: UIColor.systemGray5Color;
        label.layer.cornerRadius = nativeReferenceCornerRadius > 0 ? nativeReferenceCornerRadius : 5;
        label.layer.masksToBounds = YES;
        label.userInteractionEnabled = YES;
        [cell.contentView addSubview:label];
        NSLayoutConstraint *width = [label.widthAnchor constraintEqualToConstant:RCInlineNoteWidth(tableView, text)];
        NSLayoutConstraint *height = [label.heightAnchor constraintEqualToConstant:RCInlineNoteHeight(tableView, text)];
        NSLayoutConstraint *left = [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:60];
        NSLayoutConstraint *top = [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:0];
        [NSLayoutConstraint activateConstraints:@[
            left,
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
            width,
            top,
            height
        ]];
        RCDecisionTapTarget *target = [RCDecisionTapTarget new];
        target.page = page;
        [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(open:)]];
        objc_setAssociatedObject(cell, &decisionTapTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &decisionLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &decisionHeightKey, height, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &decisionWidthKey, width, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &decisionTopKey, top, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &decisionLeftKey, left, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    label.font = RCDecisionPreviewFont();
    label.textColor = nativeReferenceTextColor ?: UIColor.secondaryLabelColor;
    label.backgroundColor = nativeReferenceBackgroundColor ?: UIColor.systemGray5Color;
    label.layer.cornerRadius = nativeReferenceCornerRadius > 0 ? nativeReferenceCornerRadius : 5;
    ((NSLayoutConstraint *)objc_getAssociatedObject(cell, &decisionHeightKey)).constant = RCInlineNoteHeight(tableView, text);
    ((NSLayoutConstraint *)objc_getAssociatedObject(cell, &decisionWidthKey)).constant = RCInlineNoteWidth(tableView, text);
    UIView *nativeContent = CallObject(cell, @"cellView");
    CGRect nativeBounds = CGRectNull;
    NSUInteger measureBudget = 160;
    if ([nativeContent isKindOfClass:UIView.class] && nativeContent != cell.contentView)
        RCMeasureNativeContent(nativeContent, cell.contentView, 0, &measureBudget, &nativeBounds);
    CGFloat noteHeight = RCInlineNoteHeight(tableView, text);
    NSDictionary *baseHeights = objc_getAssociatedObject(page, &decisionBaseHeightsKey);
    NSNumber *baseHeight = baseHeights[indexPath];
    CGFloat top = CGRectIsNull(nativeBounds) ? (baseHeight ? baseHeight.doubleValue : CGRectGetHeight(cell.contentView.bounds)) + 2 :
        CGRectGetMaxY(nativeBounds) + 2;
    ((NSLayoutConstraint *)objc_getAssociatedObject(cell, &decisionTopKey)).constant = top;
    if (!CGRectIsNull(nativeBounds))
        ((NSLayoutConstraint *)objc_getAssociatedObject(cell, &decisionLeftKey)).constant = CGRectGetMinX(nativeBounds);
    RCDecisionTapTarget *target = objc_getAssociatedObject(cell, &decisionTapTargetKey);
    target.page = page;
    target.messageId = messageId;
    label.text = [NSString stringWithFormat:@"  %@  ", RCDecisionPreview(text)];
    label.accessibilityLabel = [NSString stringWithFormat:@"决策咨询，%@，点按查看完整内容", RCDecisionPreview(text)];
    label.hidden = top + noteHeight > CGRectGetHeight(cell.contentView.bounds) + 1;
    [cell.contentView bringSubviewToFront:label];
}

BOOL RCRefreshInlineDecisions(NSString *latestMessageId) {
    UIViewController *page = activePage;
    if (!page || !page.view.window || !RCInlineCompatibilityCheck() ||
        objc_getAssociatedObject(page, &decisionUpdatingKey)) return NO;
    UITableView *table = CallObject(page, @"getMsgTableView");
    if (![table isKindOfClass:UITableView.class]) return NO;
    RCSyncRowSequence(page);
    BOOL visible = NO;
    // Reconfigure visible cells even when the map hasn't changed. UIKit can
    // replace a cell at the same path without changing message IDs.
    for (UITableViewCell *cell in table.visibleCells) {
        NSIndexPath *path = [table indexPathForCell:cell];
        RCConfigureInlineCell(page, table, cell, path);
        UILabel *label = objc_getAssociatedObject(cell, &decisionLabelKey);
        RCDecisionTapTarget *target = objc_getAssociatedObject(cell, &decisionTapTargetKey);
        if (label && !label.hidden && [target.messageId isEqualToString:latestMessageId]) visible = YES;
    }
    RCScheduleInlineLayout(page, table);
    return visible;
}

BOOL RCRecordInlineDecision(NSString *messageId, NSString *text) {
    if (!activePage || !messageId.length || !text.length || [messageId hasPrefix:@"observed-"] ||
        RCMessageRenderDirection(messageId) != 1) return NO;
    UIViewController *page = activePage;
    RCNotes(page)[messageId] = text;
    // Keep already displayed decisions for this page's lifetime. Disk retention
    // remains 50 newest entries; never evict an arbitrary visible note.
    RCStoreNote(page, messageId, text);
    // A one-line replacement has the same height: update in place, no row reload.
    return RCRefreshInlineDecisions(messageId);
}

@interface RCProfileSwitch : NSObject
@property (nonatomic, weak) UIViewController *page;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UIBarButtonItem *item;
- (void)changed:(UISwitch *)sender;
@end

@implementation RCProfileSwitch
- (void)changed:(UISwitch *)sender {
    if (!sender.on) { RCSetConversationEnabled(self.identifier, NO); return; }
    sender.on = NO;
    if (!RCSettingsEnabled() || !RCLoadJevAPIKey().length) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"先配置 JEV API Key"
            message:@"请先在 WcSy 设置中保存密钥并启用插件。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self.page presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开启此聊天的决策咨询？"
        message:@"当前打开此聊天时，新收到的文字消息及最多 100 条已加载对话（总计最多约 16000 字符）会发送给 JEV（api.typesafe.ai）分析。结果仅在本机显示，不会发成微信消息。关闭开关即可停止。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"允许并开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        RCProfileSwitch *control = weakSelf;
        RCSetConversationEnabled(control.identifier, YES);
        control.toggle.on = YES;
    }]];
    [self.page presentViewController:alert animated:YES completion:nil];
}
@end

void RCProfileAppeared(UIViewController *page, BOOL group) {
    if (!NSThread.isMainThread || !page.view.window || !RCProfileCompatibilityCheck(group)) return;
    Class cls = NSClassFromString(group ? @"ChatRoomInfoViewController" : @"ContactInfoViewController");
    Class contactClass = NSClassFromString(@"CContact");
    NSString *primary = group ? @"m_chatRoomContact" : @"m_contact";
    NSString *fallback = group ? @"getChatContact" : @"m_chatContact";
    if (![page isKindOfClass:cls]) return;
    NSString *identifier = nil;
    for (NSString *getter in @[primary, fallback]) {
        if (!MethodMatches(cls, getter, "@16@0:8")) continue;
        id contact = CallObject(page, getter);
        if (![contact isKindOfClass:contactClass]) continue;
        NSString *candidate = CallObject(contact, @"userName");
        if ([candidate isKindOfClass:NSString.class] && candidate.length &&
            (group ? [candidate hasSuffix:@"@chatroom"] : ![candidate hasSuffix:@"@chatroom"])) {
            identifier = candidate;
            break;
        }
    }
    if (![identifier isKindOfClass:NSString.class] || !identifier.length ||
        (group && ![identifier hasSuffix:@"@chatroom"]) ||
        (!group && [identifier hasSuffix:@"@chatroom"])) return;
    RCProfileSwitch *control = objc_getAssociatedObject(page, &profileControlKey);
    if (!control) {
        control = [RCProfileSwitch new];
        control.page = page;
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 112, 34)];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, 40, 30)];
        label.text = @"咨询";
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        [container addSubview:label];
        UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(44, 1, 60, 32)];
        toggle.onTintColor = [UIColor colorWithRed:0.03 green:0.72 blue:0.36 alpha:1];
        [toggle addTarget:control action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
        [container addSubview:toggle];
        control.toggle = toggle;
        UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:container];
        control.item = item;
        NSArray *existing = page.navigationItem.rightBarButtonItems ?: @[];
        page.navigationItem.rightBarButtonItems = [existing arrayByAddingObject:item];
        objc_setAssociatedObject(page, &profileControlKey, control, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![page.navigationItem.rightBarButtonItems containsObject:control.item]) {
        NSArray *existing = page.navigationItem.rightBarButtonItems ?: @[];
        page.navigationItem.rightBarButtonItems = [existing arrayByAddingObject:control.item];
    }
    control.identifier = identifier;
    control.toggle.on = RCConversationEnabled(identifier);
}

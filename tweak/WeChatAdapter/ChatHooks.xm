#import "WeChatAdapter.h"
#import "../Overlay/SettingsViewController.h"
#import "../Core/ConversationPolicy.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <string.h>

%group SettingsEntryHooks
%hook MoreViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RCRegisterWithPluginManager();
    RCAddFallbackSettingsEntry((UIViewController *)self);
}
%end
%end

%group ContactProfileHooks
%hook ContactInfoViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RCProfileAppeared((UIViewController *)self, NO);
}
%end
%end
%group GroupProfileHooks
%hook ChatRoomInfoViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RCProfileAppeared((UIViewController *)self, YES);
}
%end
%end

%group AlternateSettingsEntryHooks
%hook MMMoreViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RCRegisterWithPluginManager();
    RCAddFallbackSettingsEntry((UIViewController *)self);
}
%end
%end

%group VerifiedChatHooks
%hook BaseMsgContentViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RCPageAppeared((UIViewController *)self);
    __weak UIViewController *weakPage = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ if (weakPage) RCPageAppeared(weakPage); });
}
- (void)viewDidLayoutSubviews {
    %orig;
    RCPageAppeared((UIViewController *)self);
}
- (void)viewDidDisappear:(BOOL)animated {
    RCPageDisappeared((UIViewController *)self);
    %orig;
}
%end
%end

%group InlineChatHooks
%hook BaseMsgContentViewController
- (double)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    double original = %orig;
    return original + RCInlineExtraHeight((UIViewController *)self, tableView, indexPath, original);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = %orig;
    RCConfigureInlineCell((UIViewController *)self, tableView, cell, indexPath);
    return cell;
}
%end
%end

static void RCProbeNavigationChat(UINavigationController *navigation) {
    UIViewController *page = navigation.topViewController;
    Class chatClass = NSClassFromString(@"BaseMsgContentViewController");
    if (chatClass && [page isKindOfClass:chatClass]) RCPageAppeared(page);
}

static void RCScheduleNavigationChatProbe(UINavigationController *navigation) {
    __weak UINavigationController *weakNavigation = navigation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ if (weakNavigation) RCProbeNavigationChat(weakNavigation); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ if (weakNavigation) RCProbeNavigationChat(weakNavigation); });
}

%group NavigationChatFallbackHooks
%hook UINavigationController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RCScheduleNavigationChatProbe((UINavigationController *)self);
}
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    %orig;
    if ([viewController isKindOfClass:NSClassFromString(@"BaseMsgContentViewController")])
        RCScheduleNavigationChatProbe((UINavigationController *)self);
}
- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    UIViewController *popped = %orig;
    if ([popped isKindOfClass:NSClassFromString(@"BaseMsgContentViewController")]) RCPageDisappeared(popped);
    RCScheduleNavigationChatProbe((UINavigationController *)self);
    return popped;
}
%end
%end

static BOOL RCSettingsHookCompatible(Class cls) {
    if (!cls || ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"8.0.78"] ||
        !NSClassFromString(@"BaseMsgContentViewController")) return NO;
    Method method = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    return method && strcmp(method_getTypeEncoding(method), "v20@0:8B16") == 0;
}

static BOOL settingsHookInstalled = NO;
static BOOL alternateSettingsHookInstalled = NO;
static BOOL chatHookInstalled = NO;
static BOOL inlineHookInstalled = NO;
static BOOL contactHookInstalled = NO;
static BOOL groupHookInstalled = NO;
static BOOL navigationFallbackInstalled = NO;

BOOL RCHookEngineAvailable(void) { return dlsym(RTLD_DEFAULT, "MSHookMessageEx") != NULL; }
BOOL RCChatHookInstalled(void) { return chatHookInstalled; }

static void RCInstallHooksAfterLaunch(void) {
    if (!NSThread.isMainThread) return;
    RCRegisterWithPluginManager();
    if (!RCHookEngineAvailable()) return;
    if (!settingsHookInstalled && RCSettingsHookCompatible(NSClassFromString(@"MoreViewController"))) {
        %init(SettingsEntryHooks);
        settingsHookInstalled = YES;
    }
    if (!alternateSettingsHookInstalled && RCSettingsHookCompatible(NSClassFromString(@"MMMoreViewController"))) {
        %init(AlternateSettingsEntryHooks);
        alternateSettingsHookInstalled = YES;
    }
    if (RCStaticCompatibilityCheck()) {
        if (!chatHookInstalled) { %init(VerifiedChatHooks); chatHookInstalled = YES; }
        if (!navigationFallbackInstalled) { %init(NavigationChatFallbackHooks); navigationFallbackInstalled = YES; }
        if (!inlineHookInstalled && RCInlineCompatibilityCheck()) {
            %init(InlineChatHooks); inlineHookInstalled = YES;
        }
        if (!contactHookInstalled && RCProfileCompatibilityCheck(NO)) {
            %init(ContactProfileHooks); contactHookInstalled = YES;
        }
        if (!groupHookInstalled && RCProfileCompatibilityCheck(YES)) {
            %init(GroupProfileHooks); groupHookInstalled = YES;
        }
    }
}

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.tencent.xin"]) return;
    // Do not touch WeChat classes during dyld initialization.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            RCInstallHooksAfterLaunch();
        }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            RCInstallHooksAfterLaunch();
        }];
    [[NSNotificationCenter defaultCenter] addObserverForName:RCConversationChangedNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            RCConversationPolicyChanged(note.object);
        }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ RCInstallHooksAfterLaunch(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ RCInstallHooksAfterLaunch(); });
}

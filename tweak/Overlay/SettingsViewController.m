#import "SettingsViewController.h"
#import "../Core/RemoteGenerationProvider.h"
#import "../WeChatAdapter/WeChatAdapter.h"
#import "ReplyOverlay.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString * const RCSettingsChangedNotification = @"com.wcsy.reply.settingsChanged";
static NSString * const kEnabledKey = @"com.wcsy.reply.enabled";
static BOOL registeredWithManager = NO;
static char launcherKey;

BOOL RCSettingsEnabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:kEnabledKey];
}

@interface RCSettingsLauncher : NSObject
@property (nonatomic, weak) UIViewController *source;
- (void)openSettings;
@end
@implementation RCSettingsLauncher
- (void)openSettings {
    RCSettingsViewController *settings = [RCSettingsViewController new];
    if (self.source.navigationController) {
        [self.source.navigationController pushViewController:settings animated:YES];
    } else {
        [self.source presentViewController:[[UINavigationController alloc] initWithRootViewController:settings]
            animated:YES completion:nil];
    }
}
@end

void RCRegisterWithPluginManager(void) {
    if (registeredWithManager || !NSThread.isMainThread) return;
    Class cls = NSClassFromString(@"WCPluginsMgr");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL registerSelector = NSSelectorFromString(@"registerControllerWithTitle:version:controller:");
    if (!cls || ![cls respondsToSelector:shared]) return;
    NSMethodSignature *sharedSignature = [cls methodSignatureForSelector:shared];
    if (sharedSignature.numberOfArguments != 2 || sharedSignature.methodReturnType[0] != '@') return;
    id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    if (!manager || ![manager respondsToSelector:registerSelector]) return;
    NSMethodSignature *signature = [manager methodSignatureForSelector:registerSelector];
    if (signature.numberOfArguments != 5 || strcmp(signature.methodReturnType, @encode(void)) != 0) return;
    for (NSUInteger i = 2; i < 5; i++) if ([signature getArgumentTypeAtIndex:i][0] != '@') return;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(manager, registerSelector,
        @"WcSy 决策咨询", @"0.2.25", @"RCSettingsViewController");
    registeredWithManager = YES;
}

void RCAddFallbackSettingsEntry(UIViewController *controller) {
    if (!controller.navigationItem ||
        objc_getAssociatedObject(controller, &launcherKey)) return;
    RCSettingsLauncher *launcher = [RCSettingsLauncher new];
    launcher.source = controller;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"决策咨询"
        style:UIBarButtonItemStylePlain target:launcher action:@selector(openSettings)];
    NSArray *existing = controller.navigationItem.rightBarButtonItems ?: @[];
    controller.navigationItem.rightBarButtonItems = [existing arrayByAddingObject:item];
    objc_setAssociatedObject(controller, &launcherKey, launcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@interface RCSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *jevField;
@property (nonatomic, copy) NSString *statusText;
@end

@implementation RCSettingsViewController
- (UITextField *)keyField:(NSString *)name savedValue:(NSString *)value {
    UITextField *field = [UITextField new];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.borderStyle = UITextBorderStyleNone;
    field.secureTextEntry = NO;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.keyboardType = UIKeyboardTypeASCIICapable;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory = YES;
    field.placeholder = @"粘贴 API Key";
    field.accessibilityLabel = name;
    field.text = value;
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WcSy 决策咨询";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.03 green:0.72 blue:0.36 alpha:1];
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
            target:self action:@selector(close)];
    }
    _jevField = [self keyField:@"JEV API Key" savedValue:RCLoadJevAPIKey()];
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 76;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [self updateStatus];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateStatus];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 || section == 2 ? 1 : 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"模型服务" : section == 1 ? @"操作" : @"状态";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"当前版本只运行 JEV 决策分析；密钥保存在本机 Keychain。";
    if (section == 1) return @"在联系人或群资料页逐个开启聊天。仅分析当前打开聊天中新收到的对方文字消息，结果只在本机显示。";
    return nil;
}
- (UITableViewCell *)keyCellWithTitle:(NSString *)title field:(UITextField *)field {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.text = title;
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:field];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
        [field.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:5],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:35],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8]
    ]];
    return cell;
}
- (UITableViewCell *)textCell:(NSString *)title color:(UIColor *)color alignment:(NSTextAlignment)alignment {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    label.textAlignment = alignment;
    label.textColor = color;
    label.text = title;
    [cell.contentView addSubview:label];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
        [label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14]
    ]];
    return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 0) {
        return [self keyCellWithTitle:@"JEV API Key" field:self.jevField];
    }
    if (indexPath.section == 1) {
        return indexPath.row == 0 ? [self textCell:@"保存并启用" color:[UIColor colorWithRed:0.03 green:0.72 blue:0.36 alpha:1] alignment:NSTextAlignmentCenter] :
            [self textCell:@"关闭插件并删除密钥" color:UIColor.systemRedColor alignment:NSTextAlignmentCenter];
    }
    UITableViewCell *cell = [self textCell:self.statusText color:UIColor.secondaryLabelColor alignment:NSTextAlignmentLeft];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    [self.view endEditing:YES];
    if (indexPath.row == 0) [self saveAndEnable];
    else [self disableAndDelete];
}
- (void)close {
    if (self.navigationController.presentingViewController) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}
- (void)showStatus:(NSString *)status {
    self.statusText = status;
    if (self.tableView.window) {
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:2]]
            withRowAnimation:UITableViewRowAnimationNone];
    }
}
- (void)updateStatus {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"未知";
    [self showStatus:[NSString stringWithFormat:@"插件：%@\nJEV：%@\n微信：%@（Build %@）\n注入引擎：%@  ·  聊天 Hook：%@\n聊天接口：%@  ·  群消息：%@\n单聊资料：%@  ·  群资料：%@\n消息下方引用：%@\n引用外观：%@\n实时分析状态请在聊天页右上角「咨询」菜单查看。",
        RCSettingsEnabled() ? @"已启用" : @"已关闭",
        RCLoadJevAPIKey().length ? @"已保存" : @"未配置", version, build,
        RCHookEngineAvailable() ? @"可用" : @"缺失",
        RCChatHookInstalled() ? @"已安装" : @"未安装",
        RCStaticCompatibilityCheck() ? @"通过" : @"未通过",
        RCGroupCompatibilityCheck() ? @"通过" : @"未通过",
        RCProfileCompatibilityCheck(NO) ? @"通过" : @"未通过",
        RCProfileCompatibilityCheck(YES) ? @"通过" : @"未通过",
        RCInlineCompatibilityCheck() ? @"通过" : @"未通过（不显示咨询引用）",
        RCNativeReferenceStyleStatus()]];
}
- (void)saveAndEnable {
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *jev = [self.jevField.text stringByTrimmingCharactersInSet:space];
    if (!jev.length) {
        [self showStatus:@"请填写 JEV API Key。"];
        return;
    }
    if (!RCStoreJevAPIKey(jev)) {
        [self showStatus:@"保存密钥失败，请重试。"];
        return;
    }
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kEnabledKey];
    self.jevField.text = jev;
    [self updateStatus];
    [NSNotificationCenter.defaultCenter postNotificationName:RCSettingsChangedNotification object:nil];
}
- (void)disableAndDelete {
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:kEnabledKey];
    BOOL removedJev = RCStoreJevAPIKey(@"");
    BOOL removedDeepSeek = RCStoreAPIKey(@"");
    self.jevField.text = @"";
    if (removedJev && removedDeepSeek) [self updateStatus];
    else [self showStatus:@"插件已关闭，但删除密钥失败，请重试。"];
    [NSNotificationCenter.defaultCenter postNotificationName:RCSettingsChangedNotification object:nil];
}
@end

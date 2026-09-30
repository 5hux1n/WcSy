#import "../Core/ReplyTypes.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// This is the only boundary allowed to know WeChat private runtime objects.
// It intentionally exposes no send operation.
@interface RCWeChatAdapter : NSObject <RCChatAdapter>
@property (nonatomic, readonly) BOOL supported;
@property (nonatomic, copy, readonly) NSString *version;
- (instancetype)initWithVersion:(NSString *)version build:(NSString *)build;
@end

FOUNDATION_EXPORT BOOL RCStaticCompatibilityCheck(void);
FOUNDATION_EXPORT BOOL RCInlineCompatibilityCheck(void);
FOUNDATION_EXPORT BOOL RCGroupCompatibilityCheck(void);
FOUNDATION_EXPORT BOOL RCHookEngineAvailable(void);
FOUNDATION_EXPORT BOOL RCChatHookInstalled(void);
FOUNDATION_EXPORT NSString *RCChatRuntimeStatus(void);
FOUNDATION_EXPORT NSString *RCNativeReferenceStyleStatus(void);
FOUNDATION_EXPORT NSString *RCDraftRuntimeStatus(void);
FOUNDATION_EXPORT BOOL RCProfileCompatibilityCheck(BOOL group);
FOUNDATION_EXPORT void RCPageAppeared(UIViewController *page);
FOUNDATION_EXPORT void RCPageDisappeared(UIViewController *page);
FOUNDATION_EXPORT void RCConversationPolicyChanged(NSString *identifier);
FOUNDATION_EXPORT void RCProfileAppeared(UIViewController *page, BOOL group);
FOUNDATION_EXPORT BOOL RCRecordInlineDecision(NSString *messageId, NSString *text);
FOUNDATION_EXPORT NSInteger RCMessageRenderDirection(NSString *messageId); // -1 unknown, 0 self, 1 other
FOUNDATION_EXPORT void RCObserveRenderedCell(UIViewController *page, UITableView *tableView, UITableViewCell *cell);
FOUNDATION_EXPORT BOOL RCRefreshInlineDecisions(NSString * _Nullable latestMessageId);
FOUNDATION_EXPORT CGFloat RCInlineExtraHeight(UIViewController *page, UITableView *tableView, NSIndexPath *indexPath, CGFloat originalHeight);
FOUNDATION_EXPORT void RCConfigureInlineCell(UIViewController *page, UITableView *tableView, UITableViewCell *cell, NSIndexPath *indexPath);
NS_ASSUME_NONNULL_END

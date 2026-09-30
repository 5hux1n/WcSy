#import <UIKit/UIKit.h>
#import "../Core/SessionCoordinator.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *RCAnalysisRuntimeStatus(void);
@interface RCReplyOverlay : UIView
@property (nonatomic, readonly) BOOL isAnalyzing;
- (NSString *)statusSummary;
- (instancetype)initWithCoordinator:(RCSessionCoordinator *)coordinator;
- (void)attachToChatView:(UIView *)chatView;
- (void)detach;
- (void)reanalyzeLatestIncoming;
@end
NS_ASSUME_NONNULL_END

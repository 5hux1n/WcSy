#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const RCSettingsChangedNotification;
FOUNDATION_EXPORT BOOL RCSettingsEnabled(void);
FOUNDATION_EXPORT void RCRegisterWithPluginManager(void);
FOUNDATION_EXPORT void RCAddFallbackSettingsEntry(UIViewController *controller);

@interface RCSettingsViewController : UIViewController
@end
NS_ASSUME_NONNULL_END

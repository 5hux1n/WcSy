#import <UIKit/UIKit.h>
#import "../tweak/Overlay/SettingsViewController.h"

@interface SettingsPreviewDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SettingsPreviewDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application; (void)launchOptions;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc]
        initWithRootViewController:[RCSettingsViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SettingsPreviewDelegate.class));
    }
}

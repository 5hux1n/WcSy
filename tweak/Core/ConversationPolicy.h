#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const RCConversationChangedNotification;
FOUNDATION_EXPORT BOOL RCConversationEnabled(NSString *identifier);
FOUNDATION_EXPORT void RCSetConversationEnabled(NSString *identifier, BOOL enabled);

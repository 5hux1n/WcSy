#import "ConversationPolicy.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const RCConversationChangedNotification = @"com.wcsy.reply.conversationChanged";

static NSString *RCConversationKey(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    NSData *data = [identifier dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *key = [@"com.wcsy.reply.conversation." mutableCopy];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [key appendFormat:@"%02x", digest[i]];
    return key;
}

BOOL RCConversationEnabled(NSString *identifier) {
    NSString *key = RCConversationKey(identifier);
    return key && [NSUserDefaults.standardUserDefaults boolForKey:key];
}

void RCSetConversationEnabled(NSString *identifier, BOOL enabled) {
    NSString *key = RCConversationKey(identifier);
    if (!key) return;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:RCConversationChangedNotification object:identifier];
}

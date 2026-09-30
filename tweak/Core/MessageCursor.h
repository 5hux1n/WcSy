#import "ReplyTypes.h"

// Tracks arrivals without treating reloaded history as new traffic.
@interface RCMessageCursor : NSObject
- (instancetype)initWithMessages:(NSArray<RCMessage *> *)messages emptySince:(long long)timestampMs;
- (NSArray<RCMessage *> *)consume:(NSArray<RCMessage *> *)messages;
@end

#import "MessageCursor.h"

@interface RCMessageCursor ()
@property (nonatomic, strong) NSMutableSet<NSString *> *seen;
@property (nonatomic) long long timestampMs;
@property (nonatomic) long long largestLocalId;
@end

@implementation RCMessageCursor
- (instancetype)initWithMessages:(NSArray<RCMessage *> *)messages emptySince:(long long)timestampMs {
    if ((self = [super init])) {
        _seen = [NSMutableSet set];
        _timestampMs = messages.count ? 0 : timestampMs;
        for (RCMessage *message in messages) {
            if (!message.localId.length || [message.localId hasPrefix:@"observed-"]) continue;
            [_seen addObject:message.localId];
            _timestampMs = MAX(_timestampMs, message.timestampMs);
            _largestLocalId = MAX(_largestLocalId, message.localId.longLongValue);
        }
    }
    return self;
}
- (NSArray<RCMessage *> *)consume:(NSArray<RCMessage *> *)messages {
    NSMutableArray *arrivals = [NSMutableArray array];
    long long newestTime = self.timestampMs, newestId = self.largestLocalId;
    // Scan the window, not only its last item: WeChat can insert a received
    // message ahead of an unchanged trailing row or expose its local ID later.
    for (RCMessage *message in messages) {
        if (!message.localId.length || [message.localId hasPrefix:@"observed-"] ||
            [self.seen containsObject:message.localId]) continue;
        BOOL newer = message.timestampMs > self.timestampMs ||
            message.localId.longLongValue > self.largestLocalId ||
            (self.seen.count == 0 && message.timestampMs == self.timestampMs);
        // A text placeholder isn't consumed before its body becomes readable.
        if ([message.kind isEqualToString:@"text"] && !message.text.length) continue;
        [self.seen addObject:message.localId];
        if (newer) {
            [arrivals addObject:message];
            newestTime = MAX(newestTime, message.timestampMs);
            newestId = MAX(newestId, message.localId.longLongValue);
        }
    }
    self.timestampMs = newestTime;
    self.largestLocalId = newestId;
    if (self.seen.count > 2048) {
        [self.seen intersectSet:[NSSet setWithArray:[messages valueForKey:@"localId"]]];
    }
    return arrivals;
}
@end

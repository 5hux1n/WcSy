#import "ContextEngine.h"
#import <CommonCrypto/CommonDigest.h>

@implementation RCContextEngine

+ (NSString *)hashForMessages:(NSArray<RCMessage *> *)messages {
    NSMutableData *data = [NSMutableData data];
    for (RCMessage *message in messages) {
        NSArray<NSString *> *fields = @[
            message.localId ?: @"", message.senderId ?: @"",
            message.direction ?: @"", message.kind ?: @"",
            message.text ?: @"", [@(message.timestampMs) stringValue],
            message.recalled ? @"1" : @"0", message.partial ? @"1" : @"0"
        ];
        for (NSString *field in fields) {
            NSData *bytes = [field dataUsingEncoding:NSUTF8StringEncoding];
            uint64_t length = CFSwapInt64HostToBig((uint64_t)bytes.length);
            [data appendBytes:&length length:sizeof(length)];
            [data appendData:bytes];
        }
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}

+ (RCContextSnapshot *)buildWithMessages:(NSArray<RCMessage *> *)messages
                                  session:(RCSessionHandle *)session
                                requestId:(NSString *)requestId
                                    limit:(NSUInteger)limit
                              maxCharacters:(NSUInteger)maxCharacters {
    return [self buildWithMessages:messages session:session requestId:requestId limit:limit
        maxCharacters:maxCharacters preserveObservationOrder:NO];
}

+ (RCContextSnapshot *)buildWithMessages:(NSArray<RCMessage *> *)messages
                                  session:(RCSessionHandle *)session
                                requestId:(NSString *)requestId
                                    limit:(NSUInteger)limit
                            maxCharacters:(NSUInteger)maxCharacters
                 preserveObservationOrder:(BOOL)preserveOrder {
    // A stable local ID deduplicates repeated UI updates; the latest observation wins.
    NSMutableDictionary<NSString *, RCMessage *> *byId = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *observedOrder = [NSMutableDictionary dictionary];
    NSUInteger observation = 0;
    for (RCMessage *message in messages) {
        if (message.localId.length) {
            byId[message.localId] = message;
            observedOrder[message.localId] = @(observation);
        }
        observation++;
    }
    NSArray<RCMessage *> *sorted = [[byId allValues] sortedArrayUsingComparator:^NSComparisonResult(RCMessage *a, RCMessage *b) {
        if (!preserveOrder && a.timestampMs != b.timestampMs) return a.timestampMs < b.timestampMs ? NSOrderedAscending : NSOrderedDescending;
        NSUInteger aOrder = observedOrder[a.localId].unsignedIntegerValue;
        NSUInteger bOrder = observedOrder[b.localId].unsignedIntegerValue;
        return aOrder < bOrder ? NSOrderedAscending : aOrder > bOrder ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger cap = MIN(MAX(limit, 1), 100);
    NSUInteger budget = MIN(MAX(maxCharacters, 1), 16000);
    NSMutableArray<RCMessage *> *selected = [NSMutableArray array];
    NSUInteger used = 0;
    BOOL partial = sorted.count > cap;
    NSString *fullHash = [self hashForMessages:sorted];
    for (RCMessage *message in [sorted reverseObjectEnumerator]) {
        if (selected.count >= cap) break;
        NSUInteger cost = message.text.length + 32;
        if (selected.count && used + cost > budget) { partial = YES; break; }
        RCMessage *copy = [RCMessage new];
        copy.localId = message.localId;
        copy.senderId = message.senderId;
        copy.direction = message.direction;
        copy.kind = message.kind;
        copy.timestampMs = message.timestampMs;
        copy.recalled = message.recalled;
        copy.partial = message.partial;
        if (cost > budget) {
            NSUInteger keep = budget > 32 ? budget - 32 : 0;
            NSUInteger start = message.text.length - MIN(message.text.length, keep);
            if (start < message.text.length) {
                NSRange composed = [message.text rangeOfComposedCharacterSequenceAtIndex:start];
                if (composed.location < start) start = NSMaxRange(composed);
            }
            copy.text = [message.text substringFromIndex:start];
            copy.partial = YES;
            partial = YES;
            cost = budget;
        } else {
            copy.text = message.text;
        }
        // The newest visible message is retained, even when clipped.
        [selected insertObject:copy atIndex:0];
        used += cost;
        partial |= message.partial;
    }
    RCContextSnapshot *snapshot = [RCContextSnapshot new];
    snapshot.requestId = requestId;
    snapshot.sessionId = session.sessionId;
    snapshot.pageToken = session.pageToken;
    snapshot.messages = selected;
    snapshot.partial = partial;
    snapshot.snapshotHash = fullHash;
    return snapshot;
}
@end

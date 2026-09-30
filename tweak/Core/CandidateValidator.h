#import "ReplyTypes.h"

NS_ASSUME_NONNULL_BEGIN
@interface RCCandidateValidator : NSObject
+ (NSArray<RCCandidate *> *)validCandidates:(NSArray<RCCandidate *> *)candidates
                                snapshotHash:(NSString *)snapshotHash;
@end
NS_ASSUME_NONNULL_END

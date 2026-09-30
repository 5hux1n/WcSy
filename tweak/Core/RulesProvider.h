#import "ReplyTypes.h"

NS_ASSUME_NONNULL_BEGIN
@interface RCRulesProvider : NSObject
- (NSArray<RCCandidate *> *)candidatesForSnapshot:(RCContextSnapshot *)snapshot decision:(RCDecisionResult *)decision;
@end
NS_ASSUME_NONNULL_END

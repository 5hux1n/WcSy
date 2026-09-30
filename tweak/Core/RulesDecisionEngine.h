#import "ReplyTypes.h"

NS_ASSUME_NONNULL_BEGIN
@interface RCRulesDecisionEngine : NSObject
- (RCDecisionResult *)decide:(RCContextSnapshot *)snapshot;
@end
NS_ASSUME_NONNULL_END

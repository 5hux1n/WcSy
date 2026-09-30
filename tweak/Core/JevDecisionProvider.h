#import "ReplyTypes.h"
#import "PrivacyGate.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT RCDecisionResult * _Nullable RCParseJevDecisionResponse(NSData *data);
FOUNDATION_EXPORT NSData * _Nullable RCBuildJevRequestBody(RCContextSnapshot *snapshot);
@interface RCJevDecisionProvider : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, strong) RCPrivacyGate *privacyGate;
- (instancetype)initWithGate:(RCPrivacyGate *)gate;
- (nullable NSURLSessionDataTask *)decide:(RCContextSnapshot *)snapshot
    completion:(void (^)(RCDecisionResult * _Nullable, NSError * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END

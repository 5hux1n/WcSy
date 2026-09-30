#import "ReplyTypes.h"
#import "PrivacyGate.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSArray<RCCandidate *> * _Nullable RCParseDeepSeekResponse(NSData *data, NSString *snapshotHash);
FOUNDATION_EXPORT NSData * _Nullable RCBuildDeepSeekRequestBody(RCContextSnapshot *snapshot,
    RCDecisionResult *decision, NSString *model);
@interface RCRemoteGenerationProvider : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSURL *endpoint;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, strong) RCPrivacyGate *privacyGate;
- (instancetype)initWithEndpoint:(NSURL *)endpoint model:(NSString *)model gate:(RCPrivacyGate *)gate;
- (nullable NSURLSessionDataTask *)generate:(RCContextSnapshot *)snapshot
                                    decision:(RCDecisionResult *)decision
                                    completion:(void (^)(NSArray<RCCandidate *> * _Nullable, NSError * _Nullable))completion;
@end

// Keychain only. The key is never included in diagnostics or preferences.
FOUNDATION_EXPORT BOOL RCStoreAPIKey(NSString *key);
FOUNDATION_EXPORT NSString * _Nullable RCLoadAPIKey(void);
FOUNDATION_EXPORT BOOL RCStoreJevAPIKey(NSString *key);
FOUNDATION_EXPORT NSString * _Nullable RCLoadJevAPIKey(void);
NS_ASSUME_NONNULL_END

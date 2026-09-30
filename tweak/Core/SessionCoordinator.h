#import "ReplyTypes.h"
@class RCRemoteGenerationProvider;
@class RCJevDecisionProvider;

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, RCState) {
    RCStateIdle, RCStateCapturing, RCStateDeciding, RCStateGenerating,
    RCStateReady, RCStateNoReply, RCStateFilling, RCStateError
};

@interface RCSessionCoordinator : NSObject
@property (nonatomic, readonly) RCState state;
@property (nonatomic, copy, readonly) NSArray<RCCandidate *> *candidates;
@property (nonatomic, copy, nullable) void (^onChange)(RCState state, NSError * _Nullable error);
@property (nonatomic, strong, nullable) RCRemoteGenerationProvider *remoteProvider;
@property (nonatomic, strong, nullable) RCJevDecisionProvider *jevProvider;
- (instancetype)initWithAdapter:(id<RCChatAdapter>)adapter;
- (void)generate;
- (void)analyzeLatestWithCompletion:(void (^)(RCMessage * _Nullable message, RCDecisionResult * _Nullable decision, NSError * _Nullable error))completion;
- (void)analyzeMessageWithId:(NSString *)messageId completion:(void (^)(RCMessage * _Nullable message, RCDecisionResult * _Nullable decision, NSError * _Nullable error))completion;
- (nullable RCMessage *)latestMessage;
- (NSArray<RCMessage *> *)recentMessages;
- (void)cancel;
- (BOOL)fillCandidateAtIndex:(NSUInteger)index allowOverwrite:(BOOL)allowOverwrite error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END

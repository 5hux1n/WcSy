#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RCErrorCode) {
    RCErrorUnsupportedVersion = 1,
    RCErrorStaleSession,
    RCErrorPermissionDenied,
    RCErrorNetwork,
    RCErrorTimeout,
    RCErrorProviderInvalid,
    RCErrorInputUnavailable,
    RCErrorCancelled,
    RCErrorDraftPresent,
    RCErrorAuthentication,
    RCErrorRateLimited,
    RCErrorUnsupportedContent
};

FOUNDATION_EXPORT NSString * const RCErrorDomain;
FOUNDATION_EXPORT NSError *RCError(RCErrorCode code);

@interface RCMessage : NSObject
@property (nonatomic, copy) NSString *localId;
@property (nonatomic, copy) NSString *senderId;
@property (nonatomic, copy) NSString *direction;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic) long long timestampMs;
@property (nonatomic) BOOL recalled;
@property (nonatomic) BOOL partial;
@end

@interface RCSessionHandle : NSObject
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *pageToken;
@end

@interface RCContextSnapshot : NSObject
@property (nonatomic, copy) NSString *requestId;
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *pageToken;
@property (nonatomic, copy) NSString *snapshotHash;
@property (nonatomic, copy) NSArray<RCMessage *> *messages;
@property (nonatomic) BOOL partial;
@end

@interface RCDecisionResult : NSObject
@property (nonatomic) NSUInteger schemaVersion;
@property (nonatomic, copy) NSString *replyNeed;
@property (nonatomic, copy) NSString *intent;
@property (nonatomic, copy) NSString *tone;
@property (nonatomic, copy) NSString *risk;
@property (nonatomic, copy) NSString *strategy;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *confidence;
@property (nonatomic, copy) NSString *providerId;
@property (nonatomic, copy) NSString *modelVersion;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *judgments;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *probabilities;
@property (nonatomic) NSUInteger contextMessageCount;
@property (nonatomic) BOOL contextPartial;
@end

@interface RCCandidate : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *style;
@property (nonatomic, copy) NSString *snapshotHash;
@end

@protocol RCChatAdapter <NSObject>
- (nullable RCSessionHandle *)currentSession;
- (nullable NSArray<RCMessage *> *)recentMessagesForSession:(RCSessionHandle *)session
                                                        limit:(NSUInteger)limit
                                                        error:(NSError **)error;
- (nullable NSString *)draftForSession:(RCSessionHandle *)session error:(NSError **)error;
- (BOOL)fillDraft:(NSString *)text
          session:(RCSessionHandle *)session
     expectedHash:(NSString *)snapshotHash
   allowOverwrite:(BOOL)allowOverwrite
            error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END

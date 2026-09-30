#import "ReplyTypes.h"

NS_ASSUME_NONNULL_BEGIN
@interface RCPrivacyGate : NSObject
@property (nonatomic) BOOL remoteEnabled;
@property (nonatomic) BOOL remoteConsent;
@property (nonatomic, copy, nullable) NSString *approvedHost;
- (BOOL)authorizeRemoteURL:(NSURL *)url error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END

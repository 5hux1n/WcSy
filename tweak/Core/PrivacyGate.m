#import "PrivacyGate.h"

@implementation RCPrivacyGate
- (BOOL)authorizeRemoteURL:(NSURL *)url error:(NSError **)error {
    BOOL allowed = self.remoteEnabled && self.remoteConsent &&
        [url.scheme.lowercaseString isEqualToString:@"https"] &&
        !url.user.length && !url.password.length && !url.query.length && !url.fragment.length &&
        self.approvedHost.length &&
        [url.host.lowercaseString isEqualToString:self.approvedHost.lowercaseString];
    if (!allowed && error) *error = RCError(RCErrorPermissionDenied);
    return allowed;
}
@end

#import "CandidateValidator.h"

@implementation RCCandidateValidator
+ (NSArray<RCCandidate *> *)validCandidates:(NSArray<RCCandidate *> *)candidates
                                snapshotHash:(NSString *)snapshotHash {
    NSMutableArray<RCCandidate *> *valid = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSCharacterSet *forbidden = [NSCharacterSet controlCharacterSet];
    NSCharacterSet *invisible = [NSCharacterSet characterSetWithCharactersInString:@"\u200B\u200C\u200D\u2060\uFEFF"];
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink | NSTextCheckingTypePhoneNumber error:nil];
    for (RCCandidate *candidate in candidates) {
        NSString *text = [candidate.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![candidate.snapshotHash isEqualToString:snapshotHash] || !text.length || text.length > 240) continue;
        if ([text rangeOfCharacterFromSet:forbidden].location != NSNotFound ||
            [text rangeOfCharacterFromSet:invisible].location != NSNotFound ||
            [detector firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) continue;
        NSString *key = text.lowercaseString;
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        candidate.text = text;
        [valid addObject:candidate];
        if (valid.count == 3) break;
    }
    return valid.count >= 2 ? valid : @[];
}
@end

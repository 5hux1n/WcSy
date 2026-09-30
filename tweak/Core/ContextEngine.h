#import "ReplyTypes.h"

NS_ASSUME_NONNULL_BEGIN
@interface RCContextEngine : NSObject
+ (RCContextSnapshot *)buildWithMessages:(NSArray<RCMessage *> *)messages
                                  session:(RCSessionHandle *)session
                                requestId:(NSString *)requestId
                                    limit:(NSUInteger)limit
                              maxCharacters:(NSUInteger)maxCharacters;
+ (RCContextSnapshot *)buildWithMessages:(NSArray<RCMessage *> *)messages
                                  session:(RCSessionHandle *)session
                                requestId:(NSString *)requestId
                                    limit:(NSUInteger)limit
                            maxCharacters:(NSUInteger)maxCharacters
                 preserveObservationOrder:(BOOL)preserveOrder;
+ (NSString *)hashForMessages:(NSArray<RCMessage *> *)messages;
@end
NS_ASSUME_NONNULL_END

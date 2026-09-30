#import "SessionCoordinator.h"
#import "ContextEngine.h"
#import "RulesProvider.h"
#import "CandidateValidator.h"
#import "RemoteGenerationProvider.h"
#import "RulesDecisionEngine.h"
#import "JevDecisionProvider.h"

@interface RCSessionCoordinator ()
@property (nonatomic, strong) id<RCChatAdapter> adapter;
@property (nonatomic, strong) RCRulesProvider *provider;
@property (nonatomic, strong) RCRulesDecisionEngine *rulesDecision;
@property (nonatomic, strong, nullable) RCContextSnapshot *snapshot;
@property (nonatomic, copy, nullable) NSString *originalDraft;
@property (nonatomic, readwrite) RCState state;
@property (nonatomic, copy, readwrite) NSArray<RCCandidate *> *candidates;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *activeTask;
@end

@implementation RCSessionCoordinator
- (instancetype)initWithAdapter:(id<RCChatAdapter>)adapter {
    if ((self = [super init])) {
        _adapter = adapter;
        _provider = [RCRulesProvider new];
        _rulesDecision = [RCRulesDecisionEngine new];
        _candidates = @[];
        _state = RCStateIdle;
    }
    return self;
}

- (void)emit:(RCState)state error:(NSError *)error {
    self.state = state;
    if (self.onChange) self.onChange(state, error);
}

- (void)cancel {
    NSAssert(NSThread.isMainThread, @"Coordinator must run on the main thread");
    self.generation++;
    [self.activeTask cancel];
    self.activeTask = nil;
    self.snapshot = nil;
    self.originalDraft = nil;
    self.candidates = @[];
    [self emit:RCStateIdle error:nil];
}

- (nullable RCContextSnapshot *)captureForSession:(RCSessionHandle *)session
                                        requestId:(NSString *)requestId
                                            error:(NSError **)error {
    NSArray<RCMessage *> *messages = [self.adapter recentMessagesForSession:session limit:20 error:error];
    if (!messages) return nil;
    if (messages.count == 0) {
        if (error) *error = RCError(RCErrorProviderInvalid);
        return nil;
    }
    return [RCContextEngine buildWithMessages:messages session:session requestId:requestId limit:20 maxCharacters:4000];
}

- (BOOL)isCurrent:(RCContextSnapshot *)snapshot error:(NSError **)error {
    RCSessionHandle *now = [self.adapter currentSession];
    if (!now || ![now.sessionId isEqualToString:snapshot.sessionId] ||
        ![now.pageToken isEqualToString:snapshot.pageToken]) {
        if (error) *error = RCError(RCErrorStaleSession);
        return NO;
    }
    RCContextSnapshot *fresh = [self captureForSession:now requestId:snapshot.requestId error:error];
    if (!fresh || ![fresh.snapshotHash isEqualToString:snapshot.snapshotHash]) {
        if (error && !*error) *error = RCError(RCErrorStaleSession);
        return NO;
    }
    return YES;
}

- (void)generate {
    NSAssert(NSThread.isMainThread, @"Coordinator must run on the main thread");
    [self cancel];
    NSUInteger generation = self.generation;
    [self emit:RCStateCapturing error:nil];
    RCSessionHandle *session = [self.adapter currentSession];
    if (!session) { [self emit:RCStateError error:RCError(RCErrorUnsupportedVersion)]; return; }
    NSError *error = nil;
    RCContextSnapshot *snapshot = [self captureForSession:session requestId:NSUUID.UUID.UUIDString error:&error];
    if (!snapshot) { [self emit:RCStateError error:error ?: RCError(RCErrorProviderInvalid)]; return; }
    NSString *draft = [self.adapter draftForSession:session error:&error];
    if (!draft) { [self emit:RCStateError error:error ?: RCError(RCErrorInputUnavailable)]; return; }
    self.snapshot = snapshot;
    self.originalDraft = draft;
    RCMessage *last = snapshot.messages.lastObject;
    if (!last || ![last.direction isEqualToString:@"incoming"] || last.recalled) {
        [self emit:RCStateNoReply error:nil];
        return;
    }
    if (![last.kind isEqualToString:@"text"] || !last.text.length) {
        [self emit:RCStateError error:RCError(RCErrorUnsupportedContent)];
        return;
    }
    void (^finish)(NSArray<RCCandidate *> *, NSError *) = ^(NSArray<RCCandidate *> *generated, NSError *providerError) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.generation || self.snapshot != snapshot) return;
        self.activeTask = nil;
        if (providerError) { [self emit:RCStateError error:providerError]; return; }
        NSError *staleError = nil;
        if (![self isCurrent:snapshot error:&staleError]) {
            [self cancel];
            return;
        }
        NSString *currentDraft = [self.adapter draftForSession:session error:&staleError];
        if (!currentDraft || ![currentDraft isEqualToString:self.originalDraft]) {
            [self cancel];
            return;
        }
        NSArray<RCCandidate *> *valid = [RCCandidateValidator validCandidates:generated snapshotHash:snapshot.snapshotHash];
        if (valid.count < 2) { [self emit:RCStateError error:RCError(RCErrorProviderInvalid)]; return; }
        self.candidates = valid;
        [self emit:RCStateReady error:nil];
      });
    };
    void (^continueWithDecision)(RCDecisionResult *, NSError *) = ^(RCDecisionResult *decision, NSError *decisionError) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.generation || self.snapshot != snapshot) return;
        self.activeTask = nil;
        if (decisionError || !decision) {
            [self emit:RCStateError error:decisionError ?: RCError(RCErrorProviderInvalid)];
            return;
        }
        NSError *staleError = nil;
        if (![self isCurrent:snapshot error:&staleError]) { [self cancel]; return; }
        if ([decision.replyNeed isEqualToString:@"no_reply"]) {
            self.candidates = @[];
            [self emit:RCStateNoReply error:nil];
            return;
        }
        [self emit:RCStateGenerating error:nil];
        if (self.remoteProvider) {
            self.activeTask = [self.remoteProvider generate:snapshot decision:decision completion:finish];
        } else {
            finish([self.provider candidatesForSnapshot:snapshot decision:decision], nil);
        }
      });
    };
    [self emit:RCStateDeciding error:nil];
    if (self.remoteProvider && self.jevProvider) {
        self.activeTask = [self.jevProvider decide:snapshot completion:continueWithDecision];
    } else if (self.remoteProvider || self.jevProvider) {
        [self emit:RCStateError error:RCError(RCErrorPermissionDenied)];
    } else {
        continueWithDecision([self.rulesDecision decide:snapshot], nil);
    }
}

- (void)analyzeLatestWithCompletion:(void (^)(RCMessage *, RCDecisionResult *, NSError *))completion {
    RCMessage *latest = self.latestMessage;
    [self analyzeMessageWithId:latest.localId completion:completion];
}

- (void)analyzeMessageWithId:(NSString *)messageId completion:(void (^)(RCMessage *, RCDecisionResult *, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Coordinator must run on the main thread");
    if (!self.jevProvider) { completion(nil, nil, RCError(RCErrorPermissionDenied)); return; }
    RCSessionHandle *session = [self.adapter currentSession];
    NSError *error = nil;
    NSArray<RCMessage *> *messages = session ? [self.adapter recentMessagesForSession:session limit:100 error:&error] : nil;
    NSUInteger index = [messages indexOfObjectPassingTest:^BOOL(RCMessage *item, NSUInteger position, BOOL *stop) {
        (void)position; (void)stop;
        return [item.localId isEqualToString:messageId];
    }];
    if (!messages || index == NSNotFound) {
        completion(nil, nil, error ?: RCError(RCErrorStaleSession));
        return;
    }
    NSArray<RCMessage *> *prefix = [messages subarrayWithRange:NSMakeRange(0, index + 1)];
    RCContextSnapshot *snapshot = [RCContextEngine buildWithMessages:prefix session:session
        requestId:NSUUID.UUID.UUIDString limit:100 maxCharacters:16000 preserveObservationOrder:YES];
    snapshot.partial |= messages.count >= 100; // The loaded window may have earlier history.
    RCMessage *message = snapshot.messages.lastObject;
    if (![message.localId isEqualToString:messageId]) {
        completion(nil, nil, RCError(RCErrorStaleSession));
        return;
    }
    if (![message.direction isEqualToString:@"incoming"] || ![message.kind isEqualToString:@"text"] ||
        !message.text.length || message.recalled) { completion(nil, nil, RCError(RCErrorUnsupportedContent)); return; }
    // Each analysis owns an epoch, including when another analysis replaces it.
    NSUInteger generation = ++self.generation;
    NSString *sessionId = [session.sessionId copy];
    NSString *pageToken = [session.pageToken copy];
    NSString *targetHash = [RCContextEngine hashForMessages:@[messages[index]]];
    [self.activeTask cancel];
    self.activeTask = [self.jevProvider decide:snapshot completion:^(RCDecisionResult *decision, NSError *providerError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) { completion(nil, nil, RCError(RCErrorCancelled)); return; }
            self.activeTask = nil;
            NSError *stale = nil;
            RCSessionHandle *current = [self.adapter currentSession];
            if (!current || ![current.sessionId isEqualToString:sessionId] ||
                ![current.pageToken isEqualToString:pageToken]) {
                completion(nil, nil, RCError(RCErrorStaleSession)); return;
            }
            NSArray<RCMessage *> *fresh = [self.adapter recentMessagesForSession:current limit:100 error:&stale];
            NSUInteger freshIndex = [fresh indexOfObjectPassingTest:^BOOL(RCMessage *item, NSUInteger position, BOOL *stop) {
                (void)position; (void)stop;
                return [item.localId isEqualToString:messageId];
            }];
            if (!fresh || freshIndex == NSNotFound) {
                completion(nil, nil, stale ?: RCError(RCErrorStaleSession)); return;
            }
            // Incoming traffic may slide the context window during the request.
            // The full, unclipped target must still be exactly the same message.
            if (![[RCContextEngine hashForMessages:@[fresh[freshIndex]]] isEqualToString:targetHash]) {
                completion(nil, nil, RCError(RCErrorStaleSession)); return;
            }
            completion(message, decision, providerError);
        });
    }];
}

- (NSArray<RCMessage *> *)recentMessages {
    RCSessionHandle *session = [self.adapter currentSession];
    if (!session) return @[];
    return [self.adapter recentMessagesForSession:session limit:100 error:nil] ?: @[];
}

- (RCMessage *)latestMessage {
    RCSessionHandle *session = [self.adapter currentSession];
    if (!session) return nil;
    return [self.adapter recentMessagesForSession:session limit:1 error:nil].lastObject;
}

- (BOOL)fillCandidateAtIndex:(NSUInteger)index allowOverwrite:(BOOL)allowOverwrite error:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Coordinator must run on the main thread");
    if (self.state != RCStateReady || index >= self.candidates.count || !self.snapshot) {
        if (error) *error = RCError(RCErrorStaleSession);
        return NO;
    }
    RCContextSnapshot *snapshot = self.snapshot;
    if (![self isCurrent:snapshot error:error]) { [self cancel]; return NO; }
    RCSessionHandle *session = [self.adapter currentSession];
    NSString *draft = [self.adapter draftForSession:session error:error];
    if (!draft) return NO;
    if (![draft isEqualToString:self.originalDraft]) {
        if (error) *error = RCError(RCErrorStaleSession);
        [self cancel];
        return NO;
    }
    if (draft.length && !allowOverwrite) {
        if (error) *error = RCError(RCErrorDraftPresent);
        return NO;
    }
    [self emit:RCStateFilling error:nil];
    BOOL success = [self.adapter fillDraft:self.candidates[index].text session:session
                             expectedHash:snapshot.snapshotHash allowOverwrite:allowOverwrite error:error];
    if (success) [self cancel];
    else [self emit:RCStateError error:(error ? *error : nil) ?: RCError(RCErrorInputUnavailable)];
    return success;
}
@end

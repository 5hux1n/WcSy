#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework Security \
  -I tweak/Core tests/CoreTests.m tweak/Core/ReplyTypes.m tweak/Core/ContextEngine.m \
  tweak/Core/PrivacyGate.m tweak/Core/RulesProvider.m tweak/Core/CandidateValidator.m \
  tweak/Core/ConversationPolicy.m \
  tweak/Core/RulesDecisionEngine.m tweak/Core/JevDecisionProvider.m \
  tweak/Core/RemoteGenerationProvider.m tweak/Core/SessionCoordinator.m tweak/Core/MessageCursor.m tweak/Core/DecisionSchema.m \
  -o .build/core-tests
.build/core-tests

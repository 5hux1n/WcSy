#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework Security \
  -I tweak/Core tests/JevScenarioPayloads.m tweak/Core/ReplyTypes.m tweak/Core/ContextEngine.m \
  tweak/Core/DecisionSchema.m tweak/Core/JevDecisionProvider.m tweak/Core/PrivacyGate.m \
  tweak/Core/RemoteGenerationProvider.m -o .build/jev-scenarios
.build/jev-scenarios tests/fixtures/jev-scenarios.json > .build/jev-scenario-payloads.json
python3 - <<'PY'
import json
from pathlib import Path
cases = json.loads(Path('.build/jev-scenario-payloads.json').read_text())
assert len(cases) == 10
for case in cases:
    request = case['request']
    for field, values in case['expected'].items():
        assert set(values) <= request['questions'][field]['criteria'].keys()
    state = request['state']
    assert state['target']['index'] == len(state['messages']) - 1
    if case['id'] == 'group_other':
        assert state['conversationType'] == 'group'
        assert len({m['speaker'] for m in state['messages']}) == 3
    if case['id'] == 'media_missing':
        assert state['context']['incomplete']
print('10 scenario payload checks passed (offline; no model quality claim)')
print('request byte range:', min(len(json.dumps(c['request'], ensure_ascii=False).encode()) for c in cases),
      max(len(json.dumps(c['request'], ensure_ascii=False).encode()) for c in cases))
PY

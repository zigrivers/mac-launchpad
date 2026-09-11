#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
fixture="$(mktemp -d)"
export LAUNCHPAD_INSTRUCTION_OVERRIDES="$fixture/overrides.py"
runner=config/agents/reconcile-instruction-overrides.sh
bash "$runner" apply
assert_eq "$?" 0 "an absent optional override checkout does not block setup"
cat > "$LAUNCHPAD_INSTRUCTION_OVERRIDES" <<'PY'
import sys
print(sys.argv[1])
raise SystemExit(2 if sys.argv[1] == 'check' else 0)
PY
assert_eq "$(bash "$runner" apply)" apply "apply uses the maintained installer"
output="$(bash "$runner" check)"; status=$?
assert_eq "$output" check "check stays read-only"
assert_eq "$status" 2 "upstream drift is reported to the caller"
t_done

#!/usr/bin/env bash
# tests/test-doctorfix.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
# Source just the mapping function without running doctor: extract & eval it.
eval "$(sed -n '/^_section_modules() {/,/^}/p' lib/doctor.sh)"

assert_eq "$(_section_modules 'Safety net')"           "07-secrets.sh 08-safety.sh" "safety net -> 07 + 08"
assert_eq "$(_section_modules 'Developer experience')" "09-dx.sh"                    "dx -> 09"
assert_eq "$(_section_modules 'Foundation')"           "00-foundation.sh"           "foundation -> 00"
assert_eq "$(_section_modules 'AI agents')"            "05-agents.sh"               "agents -> 05"
assert_eq "$(_section_modules 'Containers (OrbStack)')" "12-containers.sh"          "containers -> 12"
assert_eq "$(_section_modules 'Nonsense')"             ""                            "unknown -> empty"
t_done

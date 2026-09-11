#!/usr/bin/env bash
# Optional, version-guarded local overrides; their private contents stay outside Launchpad.
set -euo pipefail
mode="${1:-apply}"
case "$mode" in check|apply) ;; *) echo "Usage: $0 [check|apply]" >&2; exit 2 ;; esac
override_source="${LAUNCHPAD_INSTRUCTION_OVERRIDES:-$HOME/Developer/agent-instruction-maintenance/overrides.py}"
[ -f "$override_source" ] || exit 0
exec python3 "$override_source" "$mode"

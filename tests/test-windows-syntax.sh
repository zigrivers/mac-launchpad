#!/usr/bin/env bash
# tests/test-windows-syntax.sh — parse every .ps1 in the repo with the real
# PowerShell parser. Catches syntax errors in the Windows path from any
# machine that has pwsh (brew install --cask powershell@preview, or the
# portable GitHub-release build). Skips politely when pwsh is absent so the
# rest of the test suite still runs everywhere.
#
# Override the binary with:  PWSH=/path/to/pwsh bash tests/test-windows-syntax.sh

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PWSH="${PWSH:-pwsh}"
if ! command -v "$PWSH" >/dev/null 2>&1; then
  echo "SKIP: pwsh not found — install PowerShell to syntax-check the Windows path."
  exit 0
fi

# The target path MUST be passed as a -File argument, never interpolated into
# -Command: -Command treats trailing arguments as more script, which would
# EXECUTE the file under test instead of parsing it.
parser="$(mktemp /tmp/lp-parse-XXXXXX.ps1)"
trap 'rm -f "$parser"' EXIT
cat > "$parser" <<'PS1'
param([string]$Target)
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($Target, [ref]$null, [ref]$errs)
if ($errs) {
  $errs | ForEach-Object { "{0}:{1} {2}" -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message }
  exit 1
}
exit 0
PS1

fail=0
while IFS= read -r f; do
  if out="$("$PWSH" -NoProfile -File "$parser" "$PWD/$f" 2>&1)"; then
    echo "ok   $f"
  else
    echo "FAIL $f"
    printf '%s\n' "$out" | sed 's/^/     /'
    fail=1
  fi
done < <(find bootstrap.ps1 windows config/windows -name '*.ps1' -type f 2>/dev/null | sort)

if [ "$fail" -ne 0 ]; then
  echo "FAILED: PowerShell syntax errors above."
  exit 1
fi
echo "PASS"

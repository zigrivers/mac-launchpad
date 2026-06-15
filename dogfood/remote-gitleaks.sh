#!/usr/bin/env bash
#
# dogfood/remote-gitleaks.sh — fast, focused proof that secret scanning BLOCKS
# real secrets. Earlier probe fixtures were gitleaks-safe by design (the AWS key
# is allow-listed; a sequential ghp''_ token is low-entropy), so this runs a
# fixture MATRIX and then the EXACT command the pre-commit hook executes
# (`gitleaks git --pre-commit --staged`). Lean: bootstrap + 08-safety only — no
# Node needed, since we invoke gitleaks directly rather than the full hook chain.

set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP (brew + git) #####"
/bin/bash "$ROOT/bootstrap.sh"
echo "##### 08-safety (gitleaks + pre-commit + global gitignore) #####"
/bin/bash "$ROOT/modules/08-safety.sh" >/tmp/s.out 2>&1
echo "gitleaks: $(gitleaks version 2>/dev/null)"

echo "##### FIXTURE MATRIX — which secrets does gitleaks flag? #####"
T="$HOME/gltest"; rm -rf "$T"; mkdir -p "$T"; cd "$T" || exit 1
printf 'const k = "-----BEGIN RSA PRIVATE'' KEY-----MIIEowIBAAKCAQEAdogfoodFAKE0000-----END RSA PRIVATE'' KEY-----";\n' > f_privkey.js
printf 'const s = "sk''_live_51MFAKEdogfood00R7xK9mNvP2qWzT4yL8bHc";\n' > f_stripe.js
printf 'aws_secret_access_key = "wJalrXUtnFEMIK7MDENGbPxRfiCYzdogfoFAKE0"\n' > f_aws.js
printf 'const t = "ghp''_R7xK9mNvP2qWzT4yL8bH3cF6dG1aS5eJ0uIoQ";\n' > f_ghpat.js
printf 'const e = "AKIAIOSFODNN7EXAMPLE";\n' > f_awsexample_negativecontrol.js
gitleaks dir "$T" --report-format json --report-path /tmp/gl.json >/dev/null 2>&1
gitleaks dir "$T" >/dev/null 2>&1; echo "GITLEAKS_DIR_EXIT=$? (non-zero => secrets found)"
if command -v jq >/dev/null 2>&1 && [ -f /tmp/gl.json ]; then
  jq -r '.[] | "FOUND:\(.File | sub(".*/";"")) rule=\(.RuleID)"' /tmp/gl.json 2>/dev/null | sort -u
  echo "GITLEAKS_FINDING_COUNT=$(jq 'length' /tmp/gl.json 2>/dev/null)"
fi

echo "##### THE HOOK'S EXACT COMMAND on a staged real secret #####"
P="$HOME/blk"; rm -rf "$P"; mkdir -p "$P"; cd "$P" || exit 1
git init -q; git config user.email a@b.c; git config user.name t
# Use fixtures gitleaks actually detects (the matrix above confirmed these):
# a realistic Stripe live key + a high-entropy GitHub PAT.
printf 'const stripeKey = "sk''_live_51MFAKEdogfood00R7xK9mNvP2qWzT4yL8bHc";\nconst ghToken = "ghp''_R7xK9mNvP2qWzT4yL8bH3cF6dG1aS5eJ0uIoQ";\n' > secret.js
git add secret.js
# This is exactly what the gitleaks pre-commit hook runs:
gitleaks git --pre-commit --redact --staged >/tmp/hook.out 2>&1
rc=$?
[ "$rc" -ne 0 ] && echo "PROBE:hook_blocks_real_secret=PASS" || echo "PROBE:hook_blocks_real_secret=FAIL"
echo "GITLEAKS_HOOK_EXIT=$rc"
echo "##### GITLEAKS CHECK DONE #####"

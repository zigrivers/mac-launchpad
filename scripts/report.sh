#!/usr/bin/env bash
#
# scripts/report.sh [--share]   (a.k.a. `launchpad report`)
#
# Bundle everything a helper needs to debug your setup into ONE text file:
# the setup log, tool versions, the doctor health-check, and your OS/hardware —
# then prove it's secret-free before you share it.
#
# SAFETY (the whole point): the bundle is sanitised for obvious tokens AND
# scanned with gitleaks. If anything secret-looking survives, we DO NOT offer to
# upload it — a diagnostic that leaks your keys is worse than no diagnostic.
# `.env` files are never read. Pass --share to also create a SECRET GitHub gist
# (only happens if the scan is clean).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LP_QUIET=1   # read by common.sh to suppress its load note
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

want_share=0
[ "${1:-}" = "--share" ] && want_share=1

stamp="$(date +%Y%m%d-%H%M%S)"
bundle="$HOME/launchpad-report-${stamp}.txt"
raw="$(mktemp)"

log_step "Building a diagnostic report"

# Mask obvious secrets line-by-line. gitleaks is the real gate below; this just
# scrubs the common token shapes so they never reach disk in the first place.
sanitize() {
  sed -E \
    -e 's/(gh[pousr]_[A-Za-z0-9]{8,})/***REDACTED-GITHUB-TOKEN***/g' \
    -e 's/(github_pat_[A-Za-z0-9_]{20,})/***REDACTED-GITHUB-PAT***/g' \
    -e 's/(sk-[A-Za-z0-9_-]{16,})/***REDACTED-API-KEY***/g' \
    -e 's/(xox[baprs]-[A-Za-z0-9-]{8,})/***REDACTED-SLACK-TOKEN***/g' \
    -e 's/(AKIA[0-9A-Z]{16})/***REDACTED-AWS-KEY***/g' \
    -e 's/([Bb]earer )[A-Za-z0-9._-]{12,}/\1***REDACTED***/g' \
    -e 's/(([A-Za-z0-9_]*)(KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*)[^[:space:]]+/\1***REDACTED***/gI'
}

section() { printf '\n========== %s ==========\n' "$1" >>"$raw"; }

{
  printf 'Mac Launchpad diagnostic report\n'
  printf 'Generated: %s\n' "$(date)"
} >>"$raw"

section "System"
{
  sw_vers 2>/dev/null
  printf 'Arch: %s\n' "$(uname -m)"
  printf 'Memory: %s GB\n' "$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))"
  printf 'Model: %s\n' "$(sysctl -n hw.model 2>/dev/null || echo '?')"
} >>"$raw" 2>&1

section "Tool versions"
{
  for t in brew git gh node npm pnpm bun uv claude codex agy starship gitleaks pre-commit biome ffmpeg; do
    if command -v "$t" >/dev/null 2>&1; then
      printf '%-14s %s\n' "$t" "$("$t" --version 2>/dev/null | head -1)"
    else
      printf '%-14s (not installed)\n' "$t"
    fi
  done
} >>"$raw" 2>&1

section "Health check (doctor)"
bash "$ROOT/lib/doctor.sh" >>"$raw" 2>&1 || true

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  section "Current project (git)"
  {
    printf 'Project: %s\n' "$(basename "$(pwd)")"
    git status -sb 2>/dev/null
    printf '\nRecent checkpoints:\n'
    git log --oneline -8 2>/dev/null
  } >>"$raw" 2>&1
fi

section "Setup log (last 200 lines)"
tail -n 200 "$LAUNCHPAD_LOG" >>"$raw" 2>/dev/null || printf '(no setup log found)\n' >>"$raw"

# Write the sanitised bundle.
sanitize <"$raw" >"$bundle"
rm -f "$raw"

# --- the gate: scan the finished bundle for any surviving secrets ------------
clean=1
if have gitleaks; then
  # Discard gitleaks output (it can echo the matched secret) — we only need its
  # exit code: 0 = clean, non-zero = something found (or any error) → don't share.
  if gitleaks dir "$bundle" >/dev/null 2>&1; then
    log_ok "secret scan: clean (gitleaks found nothing)"
  else
    clean=0
    log_warn "secret scan: gitleaks flagged something — NOT sharing automatically"
  fi
else
  clean=0
  log_warn "gitleaks not installed — can't verify the report is secret-free; keeping it local"
fi

printf '\n%s✔ Report saved:%s %s\n' "${LP_GREEN}" "${LP_RESET}" "$bundle"

if [ "$clean" = "0" ]; then
  cat <<WARN

   ⚠ This report may contain something secret-looking, so it was NOT uploaded.
     Open it, review/remove anything sensitive, then share the file directly.

WARN
  exit 0
fi

# --- optional: a SECRET gist for an easy shareable link ----------------------
if [ "$want_share" = "1" ] && have gh && gh auth status >/dev/null 2>&1; then
  log_info "Uploading as a SECRET (private) GitHub gist…"
  if url="$(gh gist create --secret "$bundle" 2>/dev/null)"; then
    printf '   Shareable (secret) link: %s\n\n' "$url"
  else
    log_warn "could not create the gist — share the file above directly instead"
  fi
else
  cat <<DONE

   To get a shareable link:  launchpad report --share
   (creates a SECRET GitHub gist — only you and people you send the link to can see it)

DONE
fi

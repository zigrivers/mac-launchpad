#!/usr/bin/env bash
# lib/common.sh — shared helpers for Mac Launchpad.
# Source this at the top of every module: . "$(dirname "$0")/../lib/common.sh"
#
# Provides: logging (tee'd to a logfile), idempotency guards, file backup,
# Homebrew helpers (tap-trust aware for Homebrew >= 6.0), and idempotent MCP
# registration for Claude Code + Codex.
#
# Design notes:
#   * Sourcing is safe to do more than once (guarded below).
#   * Nothing here calls `set -e`; modules opt into their own strict mode.
#     Helpers are defensive and log failures instead of aborting the world,
#     so one missing cask never kills an unattended run — doctor.sh catches it.

# --- source guard -----------------------------------------------------------
[ -n "${LP_COMMON_SOURCED:-}" ] && return 0
LP_COMMON_SOURCED=1

# --- paths ------------------------------------------------------------------
# Resolve the repo root from this file's location so modules can find config/.
LP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LP_ROOT="$(cd "${LP_LIB_DIR}/.." >/dev/null 2>&1 && pwd)"
export LP_LIB_DIR LP_ROOT

# Hardcoded per spec: Apple Silicon only.
export BREW_PREFIX="/opt/homebrew"

# Single logfile for the whole run — the one file a stuck user sends back.
export LAUNCHPAD_LOG="${LAUNCHPAD_LOG:-$HOME/launchpad-setup.log}"

# Where new projects live (also the Filesystem-MCP scope).
export DEVELOPER_DIR="${DEVELOPER_DIR:-$HOME/Developer}"

# Honour non-interactive runs (VM test, CI): skip prompts that need a human.
LAUNCHPAD_NONINTERACTIVE="${LAUNCHPAD_NONINTERACTIVE:-0}"
export LAUNCHPAD_NONINTERACTIVE

# --- colors -----------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  LP_RED=$'\033[31m'; LP_GREEN=$'\033[32m'; LP_YELLOW=$'\033[33m'
  LP_BLUE=$'\033[34m'; LP_BOLD=$'\033[1m'; LP_DIM=$'\033[2m'; LP_RESET=$'\033[0m'
else
  LP_RED=''; LP_GREEN=''; LP_YELLOW=''; LP_BLUE=''; LP_BOLD=''; LP_DIM=''; LP_RESET=''
fi

# --- logging ----------------------------------------------------------------
_lp_ts()   { date +"%Y-%m-%d %H:%M:%S"; }
_lp_file() { printf '%s %s\n' "$(_lp_ts)" "$*" >>"$LAUNCHPAD_LOG" 2>/dev/null || true; }

log_info() { _lp_file "[ .. ] $*"; printf '   %s\n' "$*"; }
log_ok()   { _lp_file "[ OK ] $*"; printf '   %s✔%s %s\n' "$LP_GREEN" "$LP_RESET" "$*"; }
log_warn() { _lp_file "[ !! ] $*"; printf '   %s!%s %s\n' "$LP_YELLOW" "$LP_RESET" "$*"; }
log_err()  { _lp_file "[ XX ] $*"; printf '   %s✘%s %s\n' "$LP_RED" "$LP_RESET" "$*" >&2; }
log_step() { _lp_file "==> $*"; printf '\n%s==>%s %s%s%s\n' "$LP_BLUE" "$LP_RESET" "$LP_BOLD" "$*" "$LP_RESET"; }
log_note() { _lp_file "[note] $*"; printf '   %s%s%s\n' "$LP_DIM" "$*" "$LP_RESET"; }

die() { log_err "$*"; exit 1; }

# --- small utilities --------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

ensure_dir() { [ -d "$1" ] || mkdir -p "$1"; }

# Back up a file/symlink to <file>.backup.<timestamp> before we touch it.
backup_file() {
  local f="$1" b
  [ -e "$f" ] || [ -L "$f" ] || return 0
  b="${f}.backup.$(date +%Y%m%d-%H%M%S)"
  cp -a "$f" "$b" 2>/dev/null && log_note "backed up ${f} -> ${b}"
}

# Append a single line to a file if it is not already present (idempotent).
ensure_line_in_file() {
  local line="$1" file="$2"
  ensure_dir "$(dirname "$file")"
  if [ -f "$file" ] && grep -qF -- "$line" "$file"; then
    return 0
  fi
  [ -f "$file" ] && backup_file "$file"
  printf '%s\n' "$line" >>"$file"
  log_note "added to ${file}: ${line}"
}

# Replace (or create) a marker-delimited managed block in a file. New body is
# read from stdin. Re-running replaces the block in place — never duplicates.
#   replace_managed_block <file> <begin_marker> <end_marker> <<'EOF' ... EOF
replace_managed_block() {
  local file="$1" begin="$2" end="$3"
  local content tmp
  content="$(cat)"
  ensure_dir "$(dirname "$file")"
  [ -f "$file" ] && backup_file "$file"
  tmp="$(mktemp)"
  if [ -f "$file" ]; then
    awk -v b="$begin" -v e="$end" '
      $0==b {skip=1}
      skip!=1 {print}
      $0==e {skip=0}
    ' "$file" >"$tmp"
    # Drop trailing blank lines so repeated runs are byte-stable (truly idempotent),
    # then re-add exactly one blank line to separate the block.
    awk 'NF{last=NR} {line[NR]=$0} END{for(i=1;i<=last;i++) print line[i]}' "$tmp" >"${tmp}.trim" \
      && mv "${tmp}.trim" "$tmp"
    [ -s "$tmp" ] && printf '\n' >>"$tmp"
  fi
  { printf '%s\n' "$begin"; printf '%s\n' "$content"; printf '%s\n' "$end"; } >>"$tmp"
  mv "$tmp" "$file"
  log_note "updated managed block in ${file}"
}

# Force-create a symlink, backing up whatever was there if it is not already
# the symlink we want.
symlink_force() {
  local target="$1" link="$2"
  ensure_dir "$(dirname "$link")"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    log_ok "symlink ok: ${link} -> ${target}"; return 0
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    backup_file "$link"
  fi
  rm -f "$link"
  ln -sfn "$target" "$link"
  log_ok "linked ${link} -> ${target}"
}

# Resilient downloader.
download() {
  local url="$1" dest="$2"
  ensure_dir "$(dirname "$dest")"
  if curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$dest"; then
    log_ok "downloaded ${url}"
  else
    log_warn "download failed: ${url}"
    return 1
  fi
}

is_interactive() {
  [ "$LAUNCHPAD_NONINTERACTIVE" != "1" ] && [ -t 0 ]
}

# --- platform assertions ----------------------------------------------------
assert_platform() {
  if [ "$(uname -s)" != "Darwin" ]; then
    die "Mac Launchpad is for macOS only (found $(uname -s))."
  fi
  if [ "$(uname -m)" != "arm64" ]; then
    die "Apple Silicon required. This Mac reports '$(uname -m)'. Intel Macs are not supported."
  fi
  local major
  major="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
  if [ -z "$major" ] || [ "$major" -lt 14 ] 2>/dev/null; then
    die "macOS 14 (Sonoma) or newer required. Found $(sw_vers -productVersion 2>/dev/null)."
  fi
  log_ok "Platform: Apple Silicon, macOS $(sw_vers -productVersion)"
}

# --- Homebrew ---------------------------------------------------------------
ensure_brew_env() {
  if [ -x "${BREW_PREFIX}/bin/brew" ]; then
    eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
  fi
}

# Tap a third-party tap and (Homebrew >= 6.0) trust it, so its formulae/casks
# can actually load. `brew trust` is a no-op / unknown on older Homebrew, hence
# the guard.
brew_tap() {
  local tap="$1"
  if ! brew tap | grep -qx "$tap"; then
    log_info "tapping ${tap}"
    brew tap "$tap" >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "tap ${tap} failed"
  fi
  if brew help trust >/dev/null 2>&1; then
    brew trust "$tap" >>"$LAUNCHPAD_LOG" 2>&1 || log_note "could not 'brew trust ${tap}' (may be untrusted on Homebrew 6+)"
  fi
}

brew_formula_installed() { brew list --formula --versions "$1" >/dev/null 2>&1; }
brew_cask_installed()    { brew list --cask --versions "$1" >/dev/null 2>&1; }

# Install one or more formulae idempotently.
brew_install() {
  local f
  for f in "$@"; do
    if brew_formula_installed "$f"; then
      log_ok "formula present: ${f}"
    else
      log_info "installing formula: ${f}"
      if brew install "$f" >>"$LAUNCHPAD_LOG" 2>&1; then
        log_ok "installed: ${f}"
      else
        log_warn "failed to install formula: ${f} (see ${LAUNCHPAD_LOG})"
      fi
    fi
  done
}

# Install one or more casks idempotently.
brew_cask() {
  local c
  for c in "$@"; do
    if brew_cask_installed "$c"; then
      log_ok "cask present: ${c}"
    else
      log_info "installing cask: ${c}"
      if brew install --cask "$c" >>"$LAUNCHPAD_LOG" 2>&1; then
        log_ok "installed cask: ${c}"
      else
        log_warn "failed to install cask: ${c} (see ${LAUNCHPAD_LOG})"
      fi
    fi
  done
}

# --- MCP registration (idempotent) ------------------------------------------
# Claude Code: use the documented CLI, guarded by `claude mcp get`.
claude_mcp_has() { have claude && claude mcp get "$1" >/dev/null 2>&1; }

# claude_mcp_add_stdio <name> -- npx -y <pkg> [args...]
claude_mcp_add_stdio() {
  local name="$1"; shift
  have claude || { log_warn "claude not on PATH; skipping MCP '${name}'"; return 0; }
  if claude_mcp_has "$name"; then log_ok "claude MCP '${name}' already set"; return 0; fi
  if claude mcp add --scope user "$name" "$@" >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "claude MCP '${name}' added"
  else
    log_warn "claude MCP '${name}' add failed"
  fi
}

# claude_mcp_add_http <name> <url> [--header "K: V" ...]
claude_mcp_add_http() {
  local name="$1" url="$2"; shift 2
  have claude || { log_warn "claude not on PATH; skipping MCP '${name}'"; return 0; }
  if claude_mcp_has "$name"; then log_ok "claude MCP '${name}' already set"; return 0; fi
  if claude mcp add --scope user --transport http "$name" "$url" "$@" >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "claude MCP '${name}' added (http)"
  else
    log_warn "claude MCP '${name}' add failed"
  fi
}

[ -n "${LP_QUIET:-}" ] || log_note "common.sh loaded (root=${LP_ROOT})"

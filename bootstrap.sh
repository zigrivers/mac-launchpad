#!/usr/bin/env bash
#
# Mac Launchpad — Stage 0 bootstrap.
# Run this ONCE in the stock Terminal.app on a fresh Mac:
#
#   curl -fsSL https://raw.githubusercontent.com/zigrivers/mac-launchpad/main/bootstrap.sh | bash
#
# It lays the foundation (Xcode tools, Homebrew, both AI agents) and clones the
# repo, then hands off to Claude Code for the real setup. It is self-contained:
# it does NOT depend on the cloned repo, so it works fetched straight from curl.
# Everything it does is idempotent — running it twice is safe.

set -uo pipefail   # not -e: we trap failures, report them, and keep going.

LOG="$HOME/launchpad-setup.log"
# Tee all output to the logfile so a stuck run is one file to send back.
exec > >(tee -a "$LOG") 2>&1

# Overridable so forks / tests can point elsewhere.
LAUNCHPAD_REPO="${LAUNCHPAD_REPO:-https://github.com/zigrivers/mac-launchpad.git}"
LAUNCHPAD_DIR="${LAUNCHPAD_DIR:-$HOME/Developer/mac-launchpad}"

# --- minimal self-contained logging ----------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[34m'; c_bd=$'\033[1m'; c_0=$'\033[0m'
else
  c_g=''; c_y=''; c_r=''; c_b=''; c_bd=''; c_0=''
fi
say()  { printf '\n%s==>%s %s%s%s\n' "$c_b" "$c_0" "$c_bd" "$*" "$c_0"; }
ok()   { printf '   %s✔%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '   %s!%s %s\n' "$c_y" "$c_0" "$*"; }
die()  { printf '   %s✘%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

cat <<'BANNER'

   __  __            _                       _                _
  |  \/  | __ _  ___| |    __ _ _   _ _ __  | |__   __ _  __| |
  | |\/| |/ _` |/ __| |   / _` | | | | '_ \ | '_ \ / _` |/ _` |
  | |  | | (_| | (__| |__| (_| | |_| | | | || |_) | (_| | (_| |
  |_|  |_|\__,_|\___|_____\__,_|\__,_|_| |_||_.__/ \__,_|\__,_|

  Turning a fresh Mac into a complete dev machine, driven by AI.

BANNER

# --- 1. platform assertions -------------------------------------------------
say "Checking your Mac"
[ "$(uname -s)" = "Darwin" ] || die "This is for macOS only."
[ "$(uname -m)" = "arm64" ]  || die "Apple Silicon (M-series) Mac required — this one is $(uname -m)."
os_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "${os_major:-0}" -ge 14 ] 2>/dev/null || die "macOS 14 (Sonoma) or newer required — found $(sw_vers -productVersion)."
ok "Apple Silicon, macOS $(sw_vers -productVersion)"

# --- 2. Xcode Command Line Tools --------------------------------------------
say "Command Line Tools (git, compilers)"
if xcode-select -p >/dev/null 2>&1; then
  ok "already installed"
else
  warn "A small Apple window will open — click \"Install\" and wait for it to finish."
  xcode-select --install >/dev/null 2>&1 || true
  until xcode-select -p >/dev/null 2>&1; do
    sleep 15
    printf '   ...still installing Command Line Tools (this can take several minutes)\n'
  done
  ok "Command Line Tools installed"
fi

# --- 3. Homebrew ------------------------------------------------------------
say "Homebrew (the macOS package manager)"
if [ -x /opt/homebrew/bin/brew ]; then
  ok "already installed"
else
  warn "Installing Homebrew — it may ask for your Mac login password once."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed (see $LOG)."
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
# Persist brew + ~/.local/bin to future shells.
if ! grep -qs 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
  printf '\neval "$(/opt/homebrew/bin/brew shellenv)"\n' >> "$HOME/.zprofile"
fi
if ! grep -qs '.local/bin' "$HOME/.zprofile" 2>/dev/null; then
  printf 'export PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zprofile"
fi
ok "Homebrew ready ($(/opt/homebrew/bin/brew --version | head -1))"

# --- 4. The two AI agents (native installers, auto-updating) ----------------
say "Claude Code"
if command -v claude >/dev/null 2>&1; then
  ok "already installed ($(command -v claude))"
else
  curl -fsSL https://claude.ai/install.sh | bash || warn "Claude installer returned an error (see $LOG)."
fi
# Clear Gatekeeper quarantine on the native binary if present (signed by Anthropic).
[ -f "$HOME/.local/bin/claude" ] && xattr -d com.apple.quarantine "$HOME/.local/bin/claude" 2>/dev/null
command -v claude >/dev/null 2>&1 && ok "claude on PATH"

say "Codex (OpenAI)"
if command -v codex >/dev/null 2>&1; then
  ok "already installed ($(command -v codex))"
else
  curl -fsSL https://chatgpt.com/codex/install.sh | sh || warn "Codex installer returned an error (see $LOG)."
fi
export PATH="$HOME/.local/bin:$PATH"
command -v codex >/dev/null 2>&1 && ok "codex on PATH"

# --- 5. Pre-seed full-autonomy configs so Stage 1 runs unattended -----------
# These mirror config/agents/* in the repo. 05-agents.sh reconciles them to the
# repo's authoritative copies (and adds MCP servers) after the clone. We only
# write them if absent, so an existing config is never clobbered.
say "Pre-configuring both agents for unattended setup"
mkdir -p "$HOME/.claude" "$HOME/.codex"
if [ ! -f "$HOME/.claude/settings.json" ]; then
  cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "includeCoAuthoredBy": true,
  "cleanupPeriodDays": 30
}
JSON
  ok "wrote ~/.claude/settings.json (full autonomy)"
else
  ok "Claude settings already present (\$HOME/.claude/settings.json)"
fi
if [ ! -f "$HOME/.codex/config.toml" ]; then
  cat > "$HOME/.codex/config.toml" <<'TOML'
approval_policy = "never"
sandbox_mode    = "danger-full-access"
TOML
  ok "wrote ~/.codex/config.toml (full autonomy)"
else
  ok "Codex config already present (\$HOME/.codex/config.toml)"
fi

# --- 6. Clone the repo ------------------------------------------------------
say "Getting the Mac Launchpad setup files"
mkdir -p "$HOME/Developer"
if [ "${LAUNCHPAD_SKIP_CLONE:-0}" = "1" ]; then
  ok "skipping clone (LAUNCHPAD_SKIP_CLONE=1)"
elif [ -d "$LAUNCHPAD_DIR/.git" ]; then
  git -C "$LAUNCHPAD_DIR" pull --ff-only >/dev/null 2>&1 || true
  ok "updated $LAUNCHPAD_DIR"
else
  git clone --depth 1 "$LAUNCHPAD_REPO" "$LAUNCHPAD_DIR" || die "Could not clone $LAUNCHPAD_REPO (see $LOG)."
  ok "cloned to $LAUNCHPAD_DIR"
fi

# --- 7. Hand-off ------------------------------------------------------------
cat <<EOF

${c_g}${c_bd}✅ Foundation ready.${c_0} Two quick logins, then you're done:

  ${c_bd}1.${c_0} Run  ${c_b}claude${c_0}  and sign in   (needs your Claude Pro account)
  ${c_bd}2.${c_0} Run  ${c_b}codex${c_0}   and choose "Sign in with ChatGPT"  (needs your ChatGPT account)

Then start the full setup — open a new Terminal window and run:

  ${c_b}cd ~/Developer/mac-launchpad${c_0}
  ${c_b}claude${c_0}

and say:  ${c_bd}"Follow CLAUDE.md and set me up for everything."${c_0}
(swap "everything" for web-starter, full-stack, indie-game, or ml-lab to install less.)

${c_y}💡 Tip:${c_0} turn on ${c_bd}Time Machine${c_0} (System Settings ▸ General ▸ Time Machine) so you
   can always roll back. Setup log: ${LOG}

EOF

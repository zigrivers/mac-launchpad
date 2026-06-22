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

  ===============================================================

    Mac Launchpad
    Turning a fresh Mac into a complete dev machine, with AI.

  ===============================================================

  What's happening: this sets up your Mac for building software. It runs
  for a few minutes and prints a lot of text as it works — that's normal,
  and you don't need to do anything. A few things that help:

    - Stay plugged in to power if you can.
    - If it asks for your Mac password, type it and press Enter. The
      password stays invisible while you type (that's normal, not frozen).
    - You need to be signed in to an Administrator account on this Mac.

BANNER

# --- 1. platform assertions -------------------------------------------------
say "Checking your Mac"
[ "$(uname -s)" = "Darwin" ] || die "This is for macOS only."
[ "$(uname -m)" = "arm64" ]  || die "Apple Silicon (M-series) Mac required — this one is $(uname -m)."
os_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "${os_major:-0}" -ge 14 ] 2>/dev/null || die "macOS 14 (Sonoma) or newer required — found $(sw_vers -productVersion)."
ok "Apple Silicon, macOS $(sw_vers -productVersion)"
# Admin access is required: installing Homebrew and system tools needs sudo,
# which only Administrator accounts have. Check now and fail with a clear,
# actionable message rather than dying halfway through the Homebrew install.
if ! id -Gn 2>/dev/null | grep -qw admin; then
  die "This account ($(whoami)) is not an Administrator, and setup needs admin access to install tools. Either sign in as an admin user and run this again, or make this account an admin in System Settings ▸ Users & Groups (an existing admin has to do that). Then re-run this command."
fi
ok "Administrator account"

# --- 2. Xcode Command Line Tools --------------------------------------------
say "Command Line Tools (git, compilers)"
if xcode-select -p >/dev/null 2>&1; then
  ok "already installed"
else
  warn "A small Apple window will open — click \"Install\" and wait for it to finish."
  warn "(If it warns about battery power, plug in — or click \"Continue on Battery Power\".)"
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
  warn "Installing Homebrew. macOS will ask for your Mac login password —"
  warn "type it (it stays invisible) and press Enter. Needs an admin account."
  # Homebrew's NONINTERACTIVE installer will NOT prompt for a password itself —
  # it requires sudo to already work. Prime it here so it has cached credentials.
  # Without this, a fresh Mac fails with "Need sudo access on macOS".
  if ! sudo -v; then
    die "Homebrew needs administrator access, which this account doesn't have. Sign in as an admin user (System Settings ▸ Users & Groups — your account should be listed as \"Admin\"), then run this command again. (See $LOG.)"
  fi
  # Keep the sudo timestamp fresh during the install so it never re-prompts.
  ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
  sudo_keepalive=$!
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || { kill "$sudo_keepalive" 2>/dev/null; die "Homebrew install failed (see $LOG). If it mentioned sudo or admin access, make sure your macOS account is an Administrator (System Settings ▸ Users & Groups), then run this command again."; }
  kill "$sudo_keepalive" 2>/dev/null
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
elif command -v brew >/dev/null 2>&1 && brew install --cask codex >>"$LOG" 2>&1; then
  # Prefer the Homebrew cask: it ships a self-contained bottle and sidesteps the
  # npm dist-tag bug where @openai/codex fails to resolve its per-platform binary
  # ("Could not find … platform npm release assets"). Verified 2026-06-15.
  ok "Codex installed (brew --cask codex)"
else
  # Fallback to the official native installer (also npm-backed, so it can hit the
  # same dist-tag issue — hence brew is tried first).
  curl -fsSL https://chatgpt.com/codex/install.sh | sh || warn "Codex installer returned an error (see $LOG). Try: brew install --cask codex"
fi
export PATH="$HOME/.local/bin:$PATH"
command -v codex >/dev/null 2>&1 && ok "codex on PATH"

say "Antigravity CLI (agy)"
if command -v agy >/dev/null 2>&1; then
  ok "already installed ($(command -v agy))"
else
  # Native installer drops the binary at ~/.local/bin/agy, updates ~/.zprofile,
  # and de-quarantines itself on macOS (no separate xattr step needed).
  curl -fsSL https://antigravity.google/cli/install.sh | bash || warn "Antigravity installer returned an error (see $LOG)."
fi
export PATH="$HOME/.local/bin:$PATH"
command -v agy >/dev/null 2>&1 && ok "agy on PATH"

say "Google Chrome (Antigravity uses it for sign-in + browser tools)"
if [ -d "/Applications/Google Chrome.app" ]; then
  ok "already installed"
else
  /opt/homebrew/bin/brew install --cask google-chrome >>"$LOG" 2>&1 \
    && ok "installed" || warn "could not install Chrome (get it at google.com/chrome)."
fi

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
  # Retry the clone a few times: a transient network blip here is the #1 reason a
  # run ends with the agents installed but ~/Developer/mac-launchpad missing.
  n=0
  until git clone --depth 1 "$LAUNCHPAD_REPO" "$LAUNCHPAD_DIR"; do
    n=$((n + 1))
    [ "$n" -ge 3 ] && die "Could not download the setup files after 3 tries. Check your internet, then run this command again — it picks up where it left off. (See $LOG.)"
    warn "Download failed (attempt $n of 3) — retrying in 5s…"
    rm -rf "$LAUNCHPAD_DIR"   # clear any partial checkout so the next clone is clean
    sleep 5
  done
  ok "cloned to $LAUNCHPAD_DIR"
fi

# --- 7. Hand-off ------------------------------------------------------------
cat <<EOF

${c_g}${c_bd}✅ Foundation ready.${c_0}

${c_bd}First, open a NEW Terminal window${c_0} (press ${c_b}⌘N${c_0}) so the tools just
installed are ready to use. Do everything below in that new window.

Three quick logins:

  ${c_bd}1.${c_0} Run  ${c_b}claude${c_0}  and sign in   (needs your Claude Pro account)
  ${c_bd}2.${c_0} Run  ${c_b}codex${c_0}   and choose "Sign in with ChatGPT"  (needs your ChatGPT account)
  ${c_bd}3.${c_0} Run  ${c_b}agy${c_0}     and sign in with Google   (needs a Gmail / Gemini account)

${c_y}First time you run claude:${c_0} it asks you to pick a theme — just press Enter —
then opens your browser to sign in. If no browser opens, press ${c_b}c${c_0} to copy the
link, open it yourself, sign in, and paste the code it gives you back here.
If claude shows a red ${c_bd}"Bypass Permissions"${c_0} warning, choose ${c_b}2. Yes, I accept${c_0}
so it can set everything up for you without stopping at every step.

${c_y}After each login,${c_0} type ${c_b}/exit${c_0} (or press Ctrl-C twice) to come back here
before starting the next one.

Then start the full setup — in that same window run:

  ${c_b}cd ~/Developer/mac-launchpad${c_0}
  ${c_b}claude${c_0}

and say:  ${c_bd}"Follow CLAUDE.md and set me up for everything."${c_0}
(swap "everything" for web-starter, full-stack, indie-game, or ml-lab to install less.)

${c_y}💡 Tip:${c_0} turn on ${c_bd}Time Machine${c_0} (System Settings ▸ General ▸ Time Machine) so you
   can always roll back. Setup log: ${LOG}

EOF

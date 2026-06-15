#!/usr/bin/env bash
# shellcheck disable=SC2016  # check/softck args are eval'd later — $VARS must stay literal here
#
# lib/doctor.sh [profile]
#
# Green/red health check. RED = something the installer should have produced and
# didn't → exit non-zero so the orchestrator fixes it and re-runs. YELLOW =
# needs a human (sign-ins) or a GUI step (Xcode/Android SDK) — reported, but not
# a hard failure. If a profile is given, only that profile's toolchains are
# checked as hard requirements.

set -uo pipefail
export LP_QUIET=1   # read by common.sh to suppress its load note
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
. "$HERE/common.sh"
ensure_brew_env

# Discover tools the modules install, regardless of how doctor was invoked
# (login shell or not): user-local bins, bun, and the active fnm Node — which is
# where pnpm (corepack), vercel (npm -g), and bun actually live.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:$PATH"
if have fnm; then
  eval "$(fnm env 2>/dev/null)" 2>/dev/null || true
  fnm use default >/dev/null 2>&1 || true
fi

profile="${1:-}"
PASS=0; FAIL=0; WARN=0

hdr()  { printf '\n%s%s%s\n' "$LP_BOLD" "$*" "$LP_RESET"; }
_ok()  { printf '   %s✔%s %s\n' "$LP_GREEN" "$LP_RESET" "$*"; PASS=$((PASS+1)); }
_no()  { printf '   %s✘%s %s\n' "$LP_RED" "$LP_RESET" "$*"; FAIL=$((FAIL+1)); }
_wn()  { printf '   %s!%s %s\n' "$LP_YELLOW" "$LP_RESET" "$*"; WARN=$((WARN+1)); }

# check  <label> <shell-expr>   → red on failure (hard)
# softck <label> <shell-expr>   → yellow on failure (needs human/GUI)
check()  { if eval "$2" >/dev/null 2>&1; then _ok "$1"; else _no "$1"; fi; }
softck() { if eval "$2" >/dev/null 2>&1; then _ok "$1"; else _wn "$1"; fi; }

# Which areas are in scope?
area_active() {
  [ -z "$profile" ] && return 0   # no profile → check everything as hard reqs
  local pf="$LP_ROOT/profiles/${profile}.yaml"
  [ -f "$pf" ] || return 0
  grep -E '^[[:space:]]*-[[:space:]]+[A-Za-z]' "$pf" \
    | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//' \
    | grep -qx "$1"
}

printf '%s== Mac Launchpad doctor ==%s' "$LP_BOLD" "$LP_RESET"
[ -n "$profile" ] && printf '  (profile: %s)' "$profile"
printf '\n'

hdr "Foundation"
check  "Xcode Command Line Tools"      'xcode-select -p'
check  "Homebrew (/opt/homebrew)"      'test -x /opt/homebrew/bin/brew'
check  "git"                           'command -v git'
check  "fnm (Node version manager)"    'command -v fnm'
check  "Node"                          'command -v node'
check  "ripgrep / fd / bat / eza / fzf / jq" 'command -v rg && command -v fd && command -v bat && command -v eza && command -v fzf && command -v jq'
check  "GitHub CLI (gh)"               'command -v gh'
softck "GitHub authenticated"          'gh auth status'

hdr "Shell & terminal"
check  "zshrc launchpad block"         'grep -q "launchpad (zshrc)" "$HOME/.zshrc"'
check  "Starship installed"            'command -v starship'
check  "Starship config"               'test -f "$HOME/.config/starship.toml"'
check  "JetBrainsMono Nerd Font"       'brew list --cask font-jetbrains-mono-nerd-font'
check  "Alacritty"                     'brew list --cask alacritty'
check  "Alacritty config"              'test -f "$HOME/.config/alacritty/alacritty.toml"'
check  "Catppuccin Mocha theme"        'test -f "$HOME/.config/alacritty/themes/catppuccin-mocha.toml"'

hdr "Editors"
check  "VS Code (code)"                'command -v code'
check  "Cursor (cursor)"               'command -v cursor'
check  "Sublime Text (subl)"           'command -v subl'
softck "Claude Code extension (VS Code)" 'code --list-extensions 2>/dev/null | grep -qi "anthropic.claude-code"'
softck "Codex extension (VS Code)"       'code --list-extensions 2>/dev/null | grep -qi "openai.chatgpt"'

hdr "AI agents"
check  "claude on PATH"                'command -v claude'
check  "codex on PATH"                 'command -v codex'
check  "agy (Antigravity) on PATH"     'command -v agy'
check  "Google Chrome (for agy)"       'test -d "/Applications/Google Chrome.app"'
check  "Claude full-autonomy setting"  'grep -q "bypassPermissions" "$HOME/.claude/settings.json"'
check  "Codex full-autonomy setting"   'grep -Eq "approval_policy[[:space:]]*=[[:space:]]*\"never\"" "$HOME/.codex/config.toml"'
check  "agy autonomy (shell function)" 'grep -q "dangerously-skip-permissions" "$HOME/.zshrc"'
check  "Shared house-rules (Claude)"   'test -L "$HOME/.claude/CLAUDE.md"'
check  "Shared house-rules (Codex)"    'test -L "$HOME/.codex/AGENTS.md"'
check  "Shared house-rules (Antigravity)" 'test -L "$HOME/.gemini/AGENTS.md"'
softck "Claude authenticated"          'test -f "$HOME/.claude/.credentials.json"'
softck "Antigravity authenticated"     'security find-generic-password -s "Antigravity Safe Storage" >/dev/null 2>&1 || security find-generic-password -l "Antigravity Safe Storage" >/dev/null 2>&1'
# MCP config presence (live connectivity needs the agents running + signed in).
# context7/playwright/filesystem need no auth; github needs a gh login (human step).
for s in context7 playwright filesystem; do
  check "Claude MCP: $s (configured)"  "claude mcp get $s"
  check "Codex MCP: $s (configured)"   "grep -q '\\[mcp_servers.$s\\]' \"\$HOME/.codex/config.toml\""
done
softck "Claude MCP: github (needs gh login)" 'claude mcp get github'
check  "Codex MCP: github (configured)"      'grep -q "\[mcp_servers.github\]" "$HOME/.codex/config.toml"'
check  "Antigravity MCP (configured)"        'test -f "$HOME/.gemini/antigravity-cli/mcp_config.json" && grep -q context7 "$HOME/.gemini/antigravity-cli/mcp_config.json"'
_wn  "MCP live connectivity is verified once the agents are signed in (run 'claude mcp list')."
WARN=$((WARN-1))  # the line above is informational, not a real warning tally
check  "here.now skill (Claude)"       'test -f "$HOME/.claude/skills/here-now/SKILL.md"'
check  "here.now skill (Codex)"        'test -f "$HOME/.agents/skills/here-now/SKILL.md"'
check  "here.now skill (Antigravity)"  'test -f "$HOME/.gemini/antigravity-cli/skills/here-now/SKILL.md"'
softck "here.now service reachable"    'curl -fsS -o /dev/null --max-time 8 https://here.now/.well-known/agent.json'

hdr "Skills & workflow"
check  "Superpowers (Claude Code)"            'grep -q "superpowers@claude-plugins-official" "$HOME/.claude/settings.json"'
check  "Superpowers skills (Codex, degraded)" 'test -d "$HOME/.codex/skills/using-superpowers"'
check  "Superpowers skills (Antigravity, degraded)" 'test -d "$HOME/.gemini/antigravity-cli/skills/using-superpowers"'
check  "agent-browser skill (all 3 agents)"   'test -d "$HOME/.claude/skills/agent-browser" && test -d "$HOME/.codex/skills/agent-browser" && test -d "$HOME/.gemini/antigravity-cli/skills/agent-browser"'
check  "design skill (frontend-design)"       'test -d "$HOME/.claude/skills/frontend-design"'
check  "document skills (pdf/docx/pptx/xlsx)" 'test -d "$HOME/.claude/skills/pdf" && test -d "$HOME/.claude/skills/docx" && test -d "$HOME/.claude/skills/pptx" && test -d "$HOME/.claude/skills/xlsx"'
_wn  "Superpowers runs as a full plugin for Claude Code; Codex + Antigravity use the skills + AGENTS.md (degraded mode)."
WARN=$((WARN-1))  # informational, not a real warning

if area_active web; then
  hdr "Web stack"
  check  "pnpm or bun"                 'command -v pnpm || command -v bun'
  check  "OrbStack"                    'brew list --cask orbstack'
  check  "Supabase CLI"                'command -v supabase'
  check  "Postgres 16"                 'brew list postgresql@16'
  check  "cloudflared"                 'command -v cloudflared'
  check  "ngrok"                       'brew list --cask ngrok'
  check  "Vercel CLI"                  'command -v vercel'
fi

if area_active mobile; then
  hdr "Mobile stack"
  check  "watchman"                    'command -v watchman'
  check  "CocoaPods (pod)"             'command -v pod'
  check  "Temurin JDK (java)"          '/usr/libexec/java_home -V 2>/dev/null || command -v java'
  check  "Android Studio"              'brew list --cask android-studio'
  softck "Xcode.app installed"         'test -d /Applications/Xcode.app'
  softck "Android SDK (after first run)" 'test -d "$HOME/Library/Android/sdk"'
fi

if area_active games; then
  hdr "Games stack"
  check  "Godot"                       'brew list --cask godot'
  check  "Unity Hub"                   'brew list --cask unity-hub'
fi

if area_active ml; then
  hdr "ML stack"
  check  "uv"                          'command -v uv'
  check  "Ollama"                      'command -v ollama'
  check  "llama.cpp"                   'command -v llama-cli || brew list llama.cpp'
  check  "LM Studio"                   'brew list --cask lm-studio'
  check  "JupyterLab"                  'command -v jupyter || test -x "$HOME/.local/bin/jupyter"'
  softck "ml-lab Python env (torch/MLX)" 'test -x "$DEVELOPER_DIR/ml-lab/.venv/bin/python"'
fi

printf '\n%s== %d passed, %d failed, %d need attention ==%s\n' \
  "$LP_BOLD" "$PASS" "$FAIL" "$WARN" "$LP_RESET"
if [ "$WARN" -gt 0 ]; then
  printf '%s(! items usually just need a sign-in or a one-time GUI step.)%s\n' "$LP_DIM" "$LP_RESET"
fi

if [ "$FAIL" -gt 0 ]; then
  printf '%s✘ %d check(s) failed — see red lines above.%s\n' "$LP_RED" "$FAIL" "$LP_RESET"
  exit 1
fi
printf '%s✔ All required checks passed.%s\n' "$LP_GREEN" "$LP_RESET"
exit 0

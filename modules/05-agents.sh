#!/usr/bin/env bash
#
# 05-agents — the high-value module. Configures Claude Code + Codex for full
# autonomy, gives them one shared house-rules file, and wires up the same four
# MCP servers into both. Runs for every profile.
#
# Verified 2026-06 (see README for the audit):
#   * Claude autonomy: ~/.claude/settings.json {"permissions":{"defaultMode":"bypassPermissions"}}
#   * Codex autonomy:  ~/.codex/config.toml  approval_policy="never", sandbox_mode="danger-full-access"
#   * Claude MCP:  `claude mcp add --scope user …`
#   * Codex MCP:   [mcp_servers.*] tables in ~/.codex/config.toml
#   * GitHub MCP:  remote https://api.githubcopilot.com/mcp/ (old npm server-github is deprecated)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "05 · AI Agents (Claude Code + Codex)"

ensure_dir "$HOME/.claude"
ensure_dir "$HOME/.codex"

# --- 1. Full autonomy: Claude settings (deep-merged, never clobbered) -------
claude_settings="$HOME/.claude/settings.json"
repo_settings="$LP_ROOT/config/agents/claude.settings.json"
if [ ! -f "$claude_settings" ]; then
  cp -f "$repo_settings" "$claude_settings"
  log_ok "wrote ~/.claude/settings.json (full autonomy)"
elif have jq && jq -e . "$claude_settings" >/dev/null 2>&1; then
  backup_file "$claude_settings"; tmp="$(mktemp)"
  if jq -s '.[0] * .[1]' "$claude_settings" "$repo_settings" > "$tmp"; then
    mv "$tmp" "$claude_settings"; log_ok "merged full autonomy into ~/.claude/settings.json"
  else rm -f "$tmp"; log_warn "could not merge ~/.claude/settings.json"; fi
else
  backup_file "$claude_settings"; cp -f "$repo_settings" "$claude_settings"
  log_warn "replaced unparseable ~/.claude/settings.json"
fi

# --- 2. Full autonomy: Codex config (ensure keys live above any [table]) ----
codex_cfg="$HOME/.codex/config.toml"
[ -f "$codex_cfg" ] || cp -f "$LP_ROOT/config/agents/codex.config.toml" "$codex_cfg"
ensure_codex_key() {
  local key="$1" line="$2"
  if ! grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$codex_cfg"; then
    backup_file "$codex_cfg"
    { printf '%s\n' "$line"; cat "$codex_cfg"; } > "${codex_cfg}.tmp" && mv "${codex_cfg}.tmp" "$codex_cfg"
    log_ok "set ${key} in ~/.codex/config.toml"
  else
    log_ok "${key} already set in ~/.codex/config.toml"
  fi
}
ensure_codex_key approval_policy 'approval_policy = "never"'
ensure_codex_key sandbox_mode    'sandbox_mode    = "danger-full-access"'

# --- 3. One shared house-rules file for both agents -------------------------
symlink_force "$LP_ROOT/config/agents/AGENTS.md" "$HOME/.claude/CLAUDE.md"
symlink_force "$LP_ROOT/config/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"

# --- 4. Agent env in ~/.zshrc (GitHub token for the GitHub MCP server) ------
agent_env="$(mktemp)"
{
  echo '# GitHub token for the GitHub MCP server. Re-evaluated each shell, so it'
  echo '# stays valid as long as `gh` is logged in. No static secret on disk.'
  echo 'if command -v gh >/dev/null 2>&1; then export GITHUB_PAT_TOKEN="$(gh auth token 2>/dev/null)"; fi'
  if [ -n "${CONTEXT7_API_KEY:-}" ]; then
    echo "export CONTEXT7_API_KEY=\"${CONTEXT7_API_KEY}\""
  fi
} > "$agent_env"
replace_managed_block "$HOME/.zshrc" \
  "# >>> launchpad (agents) >>>" "# <<< launchpad (agents) <<<" < "$agent_env"
rm -f "$agent_env"
# Make the token available right now too, so Codex's config is testable.
if have gh; then
  GITHUB_PAT_TOKEN="$(gh auth token 2>/dev/null || true)"
  export GITHUB_PAT_TOKEN
fi

# --- 5. MCP servers for Claude Code (CLI, idempotent) -----------------------
log_info "Registering MCP servers for Claude Code…"
if [ -n "${CONTEXT7_API_KEY:-}" ]; then
  claude_mcp_add_stdio context7 -- npx -y @upstash/context7-mcp --api-key "$CONTEXT7_API_KEY"
else
  claude_mcp_add_stdio context7 -- npx -y @upstash/context7-mcp
fi
claude_mcp_add_stdio playwright -- npx -y @playwright/mcp@latest --headless --isolated
claude_mcp_add_stdio filesystem -- npx -y @modelcontextprotocol/server-filesystem "$DEVELOPER_DIR"
if gh auth status >/dev/null 2>&1; then
  claude_mcp_add_http github https://api.githubcopilot.com/mcp/ --header "Authorization: Bearer $(gh auth token)"
else
  log_warn "GitHub not authenticated — skipping GitHub MCP for Claude (run 'gh auth login', then re-run this module)"
fi

# --- 6. MCP servers for Codex (managed [mcp_servers.*] block at end of file) -
log_info "Registering MCP servers for Codex…"
ctx7_args='["-y", "@upstash/context7-mcp"]'
if [ -n "${CONTEXT7_API_KEY:-}" ]; then
  ctx7_args='["-y", "@upstash/context7-mcp", "--api-key", "'"${CONTEXT7_API_KEY}"'"]'
fi
codex_block="$(mktemp)"
cat > "$codex_block" <<TOML
[mcp_servers.context7]
command = "npx"
args = ${ctx7_args}

[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest", "--headless", "--isolated"]

[mcp_servers.filesystem]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "${DEVELOPER_DIR}"]

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_PAT_TOKEN"
TOML
replace_managed_block "$codex_cfg" \
  "# >>> launchpad mcp >>>" "# <<< launchpad mcp <<<" < "$codex_block"
rm -f "$codex_block"
log_ok "Codex MCP servers written to ~/.codex/config.toml"

# --- 7. Best-effort connectivity check (never blocks the run) ---------------
if have claude; then
  ( claude mcp list >>"$LAUNCHPAD_LOG" 2>&1 ) &
  cl_pid=$!
  ( sleep 45; kill "$cl_pid" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$cl_pid" 2>/dev/null || true
fi

log_ok "Agents configured: full autonomy, shared house-rules, 4 MCP servers each"

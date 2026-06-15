#!/usr/bin/env bash
#
# 06-skills — the Superpowers engineering-workflow framework + a curated,
# cross-agent skill set. Runs for every profile, after 05-agents.
#
# Two install mechanisms (verified against live docs + binaries 2026-06-15):
#   * Superpowers is a full framework (hooks + meta-skill), installed natively.
#       - Claude Code: `claude plugin install` (a real, scriptable CLI — slash
#         commands like /plugin are user-only and can't be scripted).
#       - Codex + Antigravity: no scriptable native path, so DEGRADED MODE —
#         install Superpowers' skill *content* via the cross-agent skills CLI
#         and let the shared AGENTS.md carry the workflow instructions.
#   * Everything else: the Vercel `skills` CLI (`npx skills`), which targets
#     claude-code, codex, and antigravity-cli in one command.
#
# Name/target corrections baked in: agy = `antigravity-cli` (not `antigravity`);
# frontend-design/skill-creator live in anthropics/skills (not vercel-labs);
# Superpowers' debug skill is `systematic-debugging`.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "06 · Agent Skills (Superpowers + curated set)"

# Need Node/npx for the skills CLI.
have fnm && eval "$(fnm env)" 2>/dev/null && fnm use default >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"
if ! have npx; then
  log_warn "npx not available yet — skills CLI needs Node. Re-run after 00-foundation."
fi

# --- Superpowers: Claude Code (native plugin via the scriptable CLI) ---------
if have claude; then
  if claude plugin list 2>/dev/null | grep -qi 'superpowers'; then
    log_ok "Superpowers already installed for Claude Code"
  elif claude plugin install superpowers@claude-plugins-official --scope user >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "Superpowers installed for Claude Code (restart 'claude' to activate)"
  else
    log_warn "Superpowers install for Claude Code failed — run: claude plugin install superpowers@claude-plugins-official"
  fi
else
  log_warn "claude not on PATH; skipping Superpowers for Claude Code"
fi
# Belt-and-suspenders: declare it enabled in settings.json so it activates on the
# next launch even if the CLI install above couldn't reach the marketplace.
if have jq && [ -f "$HOME/.claude/settings.json" ]; then
  tmp="$(mktemp)"
  if jq '.enabledPlugins["superpowers@claude-plugins-official"] = true' "$HOME/.claude/settings.json" >"$tmp" 2>/dev/null; then
    backup_file "$HOME/.claude/settings.json"; mv "$tmp" "$HOME/.claude/settings.json"
    log_ok "Superpowers enabled in ~/.claude/settings.json"
  else
    rm -f "$tmp"
  fi
fi

# --- Superpowers: Codex + Antigravity (degraded mode — skill content) --------
# Native Codex Superpowers is its interactive /plugins UI (not scriptable);
# Antigravity has no native path. Install the skills; AGENTS.md carries workflow.
if have npx; then
  if npx -y skills add obra/superpowers -g -y -a codex -a antigravity-cli </dev/null >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "Superpowers skills installed for Codex + Antigravity (degraded mode)"
  else
    log_warn "Superpowers degraded-mode install failed (see ${LAUNCHPAD_LOG})"
  fi
fi

# --- Curated cross-agent skills (all three agents) ---------------------------
SK_TARGETS="-a claude-code -a codex -a antigravity-cli"
add_skill() {  # add_skill <label> <repo> [--skill X ...]
  local label="$1"; shift
  have npx || { log_warn "npx missing; skipping ${label}"; return 0; }
  # shellcheck disable=SC2086  # SK_TARGETS intentionally word-splits into flags
  if npx -y skills add "$@" -g -y $SK_TARGETS </dev/null >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "skill: ${label}"
  else
    log_warn "skill failed: ${label} (see ${LAUNCHPAD_LOG})"
  fi
}
add_skill "agent-browser"        vercel-labs/agent-browser
add_skill "web-design-guidelines" vercel-labs/agent-skills --skill web-design-guidelines
add_skill "design + document skills (frontend-design, skill-creator, pdf, docx, pptx, xlsx)" \
  anthropics/skills --skill frontend-design --skill skill-creator --skill pdf --skill docx --skill pptx --skill xlsx

# --- skills-lock.json for reproducibility (experimental upstream feature) -----
# `npx skills` writes it to the current directory; copy into the repo if we can.
if [ -f skills-lock.json ] && [ -w "$LP_ROOT" ]; then
  cp -f skills-lock.json "$LP_ROOT/skills-lock.json" 2>/dev/null \
    && log_ok "captured skills-lock.json (restore with: npx skills experimental_install)"
fi

log_note "Skills install design/testing/doc abilities + the Superpowers workflow."
log_note "Restart 'claude' once so Superpowers activates for Claude Code."
log_ok "Skills complete"

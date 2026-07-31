#!/usr/bin/env bash
#
# sync-agent-skills.sh — distribute the user's global agent-skills across every
# coding tool on this Mac (Claude Code, Codex, Antigravity, Cursor, Grok,
# OpenCode, Zcode).
#
# Model:
#   ~/.agents/skills is the CANONICAL store. OpenCode and Zcode read it natively,
#   so nothing needs copying for those two. The other tools each read their own
#   directory, so this script mirrors the store into them:
#
#     Claude Code  ~/.claude/skills                    symlink  (superpowers via plugin)
#     Codex        ~/.codex/skills                      copy    (superpowers via ~/.codex/superpowers)
#     Antigravity  ~/.gemini/antigravity-cli/skills     copy    (superpowers via plugins/superpowers)
#     Cursor       ~/.cursor/skills                     copy    (superpowers copied here too)
#     Grok         ~/.grok/skills                       copy    (reads its own dir, not the store)
#     OpenCode     ~/.agents/skills  (+ ~/.config/opencode/skills)   native — no action
#     Zcode        ~/.agents/skills  (+ ~/.zcode/skills)             native — no action
#
# work-beads IS global as of 2026-07-31. ~/.agents/skills/work-beads holds a
# genericized copy usable by any Beads repo; nibble keeps a repo-specific
# override at nibble/.claude/skills/work-beads, which wins locally. The two have
# diverged on purpose — do not "reconcile" them by deleting either one.
# (Previously this script pruned work-beads from every global location.)
#
# Usage:
#   sync-agent-skills.sh            fill gaps only (safe; never clobbers)
#   sync-agent-skills.sh --force    also refresh existing copies (after `skills update`)
#   sync-agent-skills.sh --dry-run  print what would change, do nothing
#
set -euo pipefail

STORE="$HOME/.agents/skills"
FORCE=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# --- Skill manifest ----------------------------------------------------------
# Non-superpowers skills: go to every tool dir.
GLOBAL_SKILLS=(
  # named
  ship-it delegate-local local-ai-status local-review here-now coding-skill honest-thinking-partner
  x-api-extractor
  # taste-skill  (github.com/Leonxlnx/taste-skill)
  design-taste-frontend design-taste-frontend-v1 gpt-taste high-end-visual-design
  image-to-code imagegen-frontend-mobile imagegen-frontend-web industrial-brutalist-ui
  minimalist-ui redesign-existing-projects stitch-design-taste full-output-enforcement brandkit
  # agent-browser  (github.com/vercel-labs/agent-browser)
  agent-browser
  # ponytail  (github.com/DietrichGebert/ponytail) — governs what the agent BUILDS
  ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help
  # caveman  (github.com/JuliusBrussee/caveman) — governs how the agent TALKS
  caveman caveman-review caveman-commit caveman-compress caveman-stats caveman-help cavecrew
)
# superpowers  (github.com/obra/superpowers): Claude/Codex/Antigravity already
# have these via their own mechanisms, so they only need to reach Cursor here
# (OpenCode + Zcode get them from the store).
SUPERPOWERS_SKILLS=(
  brainstorming dispatching-parallel-agents executing-plans finishing-a-development-branch
  receiving-code-review requesting-code-review subagent-driven-development systematic-debugging
  test-driven-development using-git-worktrees using-superpowers verification-before-completion
  writing-plans writing-skills
)
# Never allowed in a global location (project-scoped only).
# (2026-07-31) work-beads was removed from this list. It is now a real global
# skill: ~/.agents/skills/work-beads is a genericized copy that any Beads repo
# can use, and nibble keeps its own repo-specific override at
# nibble/.claude/skills/work-beads. Project-local skills win over the store, so
# the two coexist. Re-adding work-beads here deletes the global copy.
FORBIDDEN_GLOBAL=( )

CLAUDE_DIR="$HOME/.claude/skills"
CODEX_DIR="$HOME/.codex/skills"
ANTIG_DIR="$HOME/.gemini/antigravity-cli/skills"
CURSOR_DIR="$HOME/.cursor/skills"
GROK_DIR="$HOME/.grok/skills"
GLOBAL_DIRS=( "$STORE" "$CLAUDE_DIR" "$CODEX_DIR" "$ANTIG_DIR" "$CURSOR_DIR" "$GROK_DIR" )

added=0; refreshed=0; skipped=0; pruned=0; missing_src=0

run() { if [ "$DRY" = 1 ]; then echo "  DRY: $*"; else eval "$@"; fi }

# copy a skill tree into a per-tool dir, excluding VCS metadata and local caches
# so they never propagate into the copies. A skill may itself be a standalone git
# repo (its own off-machine backup); the .git dir must not be duplicated 5×.
copy_skill() {
  local src="$1" target="$2"
  rsync -a \
    --exclude='.git' --exclude='__pycache__' --exclude='.pytest_cache' \
    --exclude='.venv' --exclude='venv' \
    "$src/" "$target/"
}

# ensure <skill> exists in <destdir> as <mode> (symlink|copy), sourced from the store
ensure() {
  local skill="$1" dest="$2" mode="$3"
  local src="$STORE/$skill" target="$dest/$skill"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "  !! source missing from store: $skill (run: skills add / re-seed)"; missing_src=$((missing_src+1)); return
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$FORCE" = 1 ]; then
      run "rm -rf '$target'"
      if [ "$mode" = symlink ]; then run "ln -s '$src' '$target'"; else run "copy_skill '$src' '$target'"; fi
      echo "  ~ refreshed $skill -> $dest"; refreshed=$((refreshed+1))
    else
      skipped=$((skipped+1))
    fi
    return
  fi
  [ -d "$dest" ] || run "mkdir -p '$dest'"
  if [ "$mode" = symlink ]; then run "ln -s '$src' '$target'"; else run "copy_skill '$src' '$target'"; fi
  echo "  + added $skill -> $dest"; added=$((added+1))
}

echo "== 1. Prune forbidden-global skills =========================================="
# The +"${...}" guard keeps an EMPTY FORBIDDEN_GLOBAL working under `set -u`
# on macOS bash 3.2, where a bare "${arr[@]}" on an empty array is an error.
for bad in ${FORBIDDEN_GLOBAL[@]+"${FORBIDDEN_GLOBAL[@]}"}; do
  for dir in "${GLOBAL_DIRS[@]}"; do
    if [ -e "$dir/$bad" ] || [ -L "$dir/$bad" ]; then
      run "rm -rf '$dir/$bad'"; echo "  - pruned $bad from $dir"; pruned=$((pruned+1))
    fi
  done
done
[ ${#FORBIDDEN_GLOBAL[@]} -eq 0 ] && echo "  (none configured)"

echo "== 2. Claude Code (symlink; superpowers via plugin) =========================="
for s in "${GLOBAL_SKILLS[@]}"; do ensure "$s" "$CLAUDE_DIR" symlink; done

echo "== 3. Codex (copy; superpowers via ~/.codex/superpowers) ======================"
for s in "${GLOBAL_SKILLS[@]}"; do ensure "$s" "$CODEX_DIR" copy; done

echo "== 4. Antigravity (copy; superpowers via plugins/superpowers) ================="
for s in "${GLOBAL_SKILLS[@]}"; do ensure "$s" "$ANTIG_DIR" copy; done

echo "== 5. Cursor (copy; incl. superpowers) ======================================="
for s in "${GLOBAL_SKILLS[@]}" "${SUPERPOWERS_SKILLS[@]}"; do ensure "$s" "$CURSOR_DIR" copy; done

echo "== 6. Grok (copy; reads its own ~/.grok/skills, not the store) ================"
for s in "${GLOBAL_SKILLS[@]}"; do ensure "$s" "$GROK_DIR" copy; done

echo "== 7. OpenCode + Zcode ======================================================="
echo "  (read ~/.agents/skills natively — nothing to copy)"

echo ""
echo "== Summary: +$added added, ~$refreshed refreshed, $skipped already-present, -$pruned pruned, $missing_src missing-source =="
[ "$missing_src" -eq 0 ] || { echo "WARNING: $missing_src manifest skill(s) missing from the store."; exit 1; }

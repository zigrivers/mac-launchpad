#!/usr/bin/env bash
#
# dogfood/remote-probes.sh — runs INSIDE the dogfood VM (reads the repo from its
# own location on the read-only share). A lean re-validation of the probes the
# first full run couldn't exercise: real-secret blocking (corrected fixture),
# the templates actually scaffolding + running key-free (no GNU `timeout`), and
# zshrc idempotency (with a diff). Installs only the modules the probes need.

set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"
/bin/bash "$ROOT/bootstrap.sh"
echo "##### LEAN INSTALL (00,01,05,08,09) #####"
for m in 00-foundation 01-shell 05-agents 08-safety 09-dx; do
  echo "-- module $m --"; /bin/bash "$ROOT/modules/$m.sh"
done

command -v fnm >/dev/null 2>&1 && eval "$(fnm env 2>/dev/null)" && fnm use default >/dev/null 2>&1

# Portable timeout (macOS has no GNU `timeout`): run cmd, kill it after N seconds.
run_to() { local s=$1; shift; "$@" & local p=$!; ( sleep "$s"; kill -9 "$p" 2>/dev/null ) & local k=$!; wait "$p" 2>/dev/null; local r=$?; kill "$k" 2>/dev/null; return "$r"; }

echo "##### PROBES #####"
rm -rf "$HOME/probe"; mkdir -p "$HOME/probe"
P1="$HOME/probe/p1"; mkdir -p "$P1"
/bin/bash "$ROOT/scripts/harden-project.sh" "$P1" --no-remote >/tmp/harden.out 2>&1
cd "$P1" || exit 1
test -f .git/hooks/pre-commit && echo "PROBE:harden_hook=PASS" || echo "PROBE:harden_hook=FAIL"
git rev-parse HEAD >/dev/null 2>&1 && echo "PROBE:harden_initial_commit=PASS" || echo "PROBE:harden_initial_commit=FAIL"

# Secret scanning must BLOCK a real-format secret (GitHub PAT) in a non-ignored file.
printf 'const token = "ghp''_0123456789abcdefghijklmnopqrstuvwxyz";\n' > leak.js
git add leak.js
if git commit -m try-leak >/tmp/leak.out 2>&1; then echo "PROBE:gitleaks_block=FAIL"; else echo "PROBE:gitleaks_block=PASS"; fi
git reset -q HEAD leak.js 2>/dev/null; rm -f leak.js

# Global gitignore must keep .env out of git.
printf 'SECRET=shh\n' > .env
git status --porcelain | grep -q '\.env' && echo "PROBE:gitignore_env=FAIL" || echo "PROBE:gitignore_env=PASS"
rm -f .env

# report.sh must produce a secret-free bundle.
printf 'leaked TOKEN=ghp''_FAKEdogfood1234567890ABCDEFGHijkl\n' >> "$HOME/launchpad-setup.log"
/bin/bash "$ROOT/scripts/report.sh" >/tmp/report.out 2>&1
RPT=$(ls -t "$HOME"/launchpad-report-*.txt 2>/dev/null | head -1)
if [ -n "$RPT" ] && ! grep -q 'ghp''_FAKEdogfood1234567890ABCDEFGHijkl' "$RPT"; then echo "PROBE:report_secretfree=PASS"; else echo "PROBE:report_secretfree=FAIL"; fi

# Biome formats.
cd "$P1"; printf 'const x=1\n' > fmt.ts
biome format --write fmt.ts >/dev/null 2>&1 && echo "PROBE:biome_format=PASS" || echo "PROBE:biome_format=FAIL"

# GAME template: scaffold + run key-free on :8080.
if run_to 360 /bin/bash "$ROOT/templates/game/scaffold.sh" "$HOME/probe/game" >/tmp/game.out 2>&1; then echo "PROBE:game_scaffold=PASS"; else echo "PROBE:game_scaffold=FAIL"; tail -8 /tmp/game.out; fi
if [ -f "$HOME/probe/game/package.json" ]; then
  ( cd "$HOME/probe/game" && nohup npm run dev >/tmp/gamedev.out 2>&1 & )
  sleep 25
  echo "PROBE:game_http=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 2>/dev/null)"
  pkill -f vite 2>/dev/null; pkill -f log.js 2>/dev/null
fi

# WEB template: scaffold (validates --no-linter / --no-agents-md) + run key-free on :3000.
if run_to 600 /bin/bash "$ROOT/templates/web/scaffold.sh" "$HOME/probe/web" >/tmp/web.out 2>&1; then echo "PROBE:web_scaffold=PASS"; else echo "PROBE:web_scaffold=FAIL"; tail -15 /tmp/web.out; fi
if [ -f "$HOME/probe/web/package.json" ]; then
  [ -f "$HOME/probe/web/CLAUDE.md" ] && echo "PROBE:web_no_agents_md=FAIL" || echo "PROBE:web_no_agents_md=PASS"
  grep -q '"test"' "$HOME/probe/web/package.json" && echo "PROBE:web_test_script=PASS" || echo "PROBE:web_test_script=NONE"
  ( cd "$HOME/probe/web" && nohup npm run dev >/tmp/webdev.out 2>&1 & )
  sleep 40
  echo "PROBE:web_http=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000 2>/dev/null)"
  pkill -f next 2>/dev/null
fi

# IDEMPOTENCY: re-run the managed-block modules, then diff ~/.zshrc.
cp "$HOME/.zshrc" /tmp/zshrc.before 2>/dev/null
/bin/bash "$ROOT/modules/01-shell.sh"  >/tmp/i1.out 2>&1
/bin/bash "$ROOT/modules/05-agents.sh" >/tmp/i2.out 2>&1
/bin/bash "$ROOT/modules/08-safety.sh" >/tmp/i3.out 2>&1
cp "$HOME/.zshrc" /tmp/zshrc.after 2>/dev/null
echo "IDEMP:zshrc_block_count=$(grep -c '>>> launchpad (zshrc)' "$HOME/.zshrc")"
echo "IDEMP:agents_block_count=$(grep -c '>>> launchpad (agents)' "$HOME/.zshrc")"
echo "IDEMP:codex_mcp_block_count=$(grep -c '>>> launchpad mcp' "$HOME/.codex/config.toml")"
echo "IDEMP:zshrc_diff_lines=$(diff /tmp/zshrc.before /tmp/zshrc.after 2>/dev/null | grep -c '^[<>]')"
echo "----ZSHRC-DIFF-BEGIN----"; diff /tmp/zshrc.before /tmp/zshrc.after 2>/dev/null | head -30; echo "----ZSHRC-DIFF-END----"
echo "##### PROBES DONE #####"

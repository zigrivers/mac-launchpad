#!/usr/bin/env bash
#
# dogfood/vm-dogfood.sh [profile]
#
# Extends scripts/test-in-vm.sh into a full dogfood: in ONE clean Tart VM it runs
# bootstrap -> install -> doctor, then a battery of FUNCTIONAL probes (secret
# scanning actually blocks a planted key, report.sh is secret-free, the templates
# scaffold + run key-free, Biome formats), then an IDEMPOTENCY re-run, then doctor
# again. Everything streams to one log and is marked with PROBE:/IDEMP:/DOCTOR_EXIT.
#
# Never touches the host machine. Requires tart + sshpass (auto-installed).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

IMAGE="${TART_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}"
VM="${TART_VM:-launchpad-dogfood}"
PROFILE="${1:-web-starter}"
VM_USER="${TART_VM_USER:-admin}"
VM_PASS="${TART_VM_PASS:-admin}"
SHARE_GUEST="/Volumes/My Shared Files/launchpad"
OUT="/tmp/launchpad-dogfood-${PROFILE}.log"

have tart || { brew trust cirruslabs/cli >/dev/null 2>&1 || true; brew install cirruslabs/cli/tart || die "no tart"; }
have sshpass || { brew trust hudochenkov/sshpass >/dev/null 2>&1 || true; brew install hudochenkov/sshpass/sshpass >/dev/null 2>&1 || true; }

VM_PID=""; CTRL="/tmp/launchpad-ssh-${VM}.ctl"
cleanup() {
  ssh -o ControlPath="$CTRL" -O exit "$VM_USER@${ip:-127.0.0.1}" >/dev/null 2>&1 || true
  rm -f "$CTRL"
  [ -n "$VM_PID" ] && kill "$VM_PID" >/dev/null 2>&1 || true
  tart stop "$VM" >/dev/null 2>&1 || true
  tart delete "$VM" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_step "Cloning a fresh VM: $VM"
tart pull "$IMAGE" || log_warn "pull failed (continuing if cached)"
tart delete "$VM" >/dev/null 2>&1 || true
tart clone "$IMAGE" "$VM" || die "tart clone failed"

log_step "Booting VM (headless), sharing the repo read-only"
tart run "$VM" --no-graphics --dir=launchpad:"$ROOT":ro >/dev/null 2>&1 &
VM_PID=$!
ip="$(tart ip "$VM" --wait 180 2>/dev/null)"; [ -n "$ip" ] || die "no IP"
log_ok "VM IP: $ip"

vm_ssh() {
  sshpass -p "$VM_PASS" ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o ControlMaster=auto -o ControlPath="$CTRL" -o ControlPersist=900 \
    "$VM_USER@$ip" "export PATH=\"\$HOME/.local/bin:/opt/homebrew/bin:\$PATH\"; $*"
}

log_info "Waiting for SSH…"
ok=0; for _ in $(seq 1 40); do vm_ssh true 2>/dev/null && { ok=1; break; }; sleep 5; done
[ "$ok" = 1 ] || die "no SSH"
log_ok "SSH up"

: > "$OUT"
log_step "Dogfood run (one session) — streaming to $OUT"

read -r -d '' REMOTE <<REMOTESCRIPT || true
set -o pipefail   # NOT set -u/-e: the probe battery must run to completion
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="\$HOME/.local/bin:/opt/homebrew/bin:\$PATH"
SHARE="$SHARE_GUEST"

echo "##### STAGE 0 — bootstrap #####"
/bin/bash "\$SHARE/bootstrap.sh"
echo "##### STAGE 1 — install $PROFILE #####"
/bin/bash "\$SHARE/scripts/install-profile.sh" "$PROFILE"
echo "##### DOCTOR #1 #####"
/bin/bash "\$SHARE/lib/doctor.sh" "$PROFILE"; echo "DOCTOR_EXIT=\$?"

command -v fnm >/dev/null 2>&1 && eval "\$(fnm env 2>/dev/null)" && fnm use default >/dev/null 2>&1

echo "##### FUNCTIONAL PROBES #####"
run_to() { s=\$1; shift; "\$@" & p=\$!; ( sleep \$s; kill -9 \$p 2>/dev/null ) & k=\$!; wait \$p 2>/dev/null; r=\$?; kill \$k 2>/dev/null; return \$r; }
rm -rf "\$HOME/probe"; mkdir -p "\$HOME/probe"
P1="\$HOME/probe/p1"; mkdir -p "\$P1"
/bin/bash "\$SHARE/scripts/harden-project.sh" "\$P1" --no-remote >/tmp/harden.out 2>&1
cd "\$P1"
test -f .git/hooks/pre-commit && echo "PROBE:harden_hook=PASS" || echo "PROBE:harden_hook=FAIL"
git rev-parse HEAD >/dev/null 2>&1 && echo "PROBE:harden_initial_commit=PASS" || echo "PROBE:harden_initial_commit=FAIL"
printf 'const token = "ghp''_R7xK9mNvP2qWzT4yL8bH3cF6dG1aS5eJ0uIoQ";\n' > leak.js
git add leak.js
if git commit -m "try-leak" >/tmp/leak.out 2>&1; then echo "PROBE:gitleaks_block=FAIL"; else echo "PROBE:gitleaks_block=PASS"; fi
git reset -q HEAD leak.js 2>/dev/null; rm -f leak.js
printf 'SECRET=shh\n' > .env
if git status --porcelain | grep -q '\.env'; then echo "PROBE:gitignore_env=FAIL"; else echo "PROBE:gitignore_env=PASS"; fi

printf 'leaked TOKEN=ghp''_FAKEdogfood1234567890ABCDEFGHijkl\n' >> "\$HOME/launchpad-setup.log"
/bin/bash "\$SHARE/scripts/report.sh" >/tmp/report.out 2>&1
RPT=\$(ls -t "\$HOME"/launchpad-report-*.txt 2>/dev/null | head -1)
if [ -n "\$RPT" ] && ! grep -q 'ghp''_FAKEdogfood1234567890ABCDEFGHijkl' "\$RPT"; then echo "PROBE:report_secretfree=PASS"; else echo "PROBE:report_secretfree=FAIL"; fi

cd "\$P1"; printf 'const x=1\n' > fmt.ts
if biome format --write fmt.ts >/dev/null 2>&1; then echo "PROBE:biome_format=PASS"; else echo "PROBE:biome_format=FAIL"; fi

if run_to 300 /bin/bash "\$SHARE/templates/game/scaffold.sh" "\$HOME/probe/game" >/tmp/game.out 2>&1; then echo "PROBE:game_scaffold=PASS"; else echo "PROBE:game_scaffold=FAIL"; tail -5 /tmp/game.out; fi
if [ -f "\$HOME/probe/game/package.json" ]; then
  ( cd "\$HOME/probe/game" && nohup npm run dev >/tmp/gamedev.out 2>&1 & )
  sleep 30
  echo "PROBE:game_http=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 2>/dev/null)"
  pkill -f vite 2>/dev/null; pkill -f log.js 2>/dev/null
fi

if run_to 480 /bin/bash "\$SHARE/templates/web/scaffold.sh" "\$HOME/probe/web" >/tmp/web.out 2>&1; then echo "PROBE:web_scaffold=PASS"; else echo "PROBE:web_scaffold=FAIL"; tail -10 /tmp/web.out; fi
if [ -f "\$HOME/probe/web/package.json" ]; then
  [ -f "\$HOME/probe/web/CLAUDE.md" ] && echo "PROBE:web_no_agents_md=FAIL(CLAUDE.md present)" || echo "PROBE:web_no_agents_md=PASS"
  grep -q '"test"' "\$HOME/probe/web/package.json" && echo "PROBE:web_test_script=PASS" || echo "PROBE:web_test_script=NONE"
  ( cd "\$HOME/probe/web" && nohup npm run dev >/tmp/webdev.out 2>&1 & )
  sleep 35
  echo "PROBE:web_http=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000 2>/dev/null)"
  pkill -f 'next' 2>/dev/null; pkill -f 'next-server' 2>/dev/null
fi

echo "##### IDEMPOTENCY (re-run managed-block modules) #####"
B=\$(md5 -q "\$HOME/.zshrc" 2>/dev/null); BC=\$(md5 -q "\$HOME/.codex/config.toml" 2>/dev/null)
/bin/bash "\$SHARE/modules/01-shell.sh"  >/tmp/idem1.out 2>&1
/bin/bash "\$SHARE/modules/05-agents.sh" >/tmp/idem2.out 2>&1
/bin/bash "\$SHARE/modules/08-safety.sh" >/tmp/idem3.out 2>&1
A=\$(md5 -q "\$HOME/.zshrc" 2>/dev/null); AC=\$(md5 -q "\$HOME/.codex/config.toml" 2>/dev/null)
echo "IDEMP:zshrc_block_count=\$(grep -c '>>> launchpad (zshrc)' "\$HOME/.zshrc")"
echo "IDEMP:agents_block_count=\$(grep -c '>>> launchpad (agents)' "\$HOME/.zshrc")"
echo "IDEMP:codex_mcp_block_count=\$(grep -c '>>> launchpad mcp' "\$HOME/.codex/config.toml")"
echo "IDEMP:zshrc_byte_stable=\$([ "\$B" = "\$A" ] && echo YES || echo NO)"
echo "IDEMP:codex_byte_stable=\$([ "\$BC" = "\$AC" ] && echo YES || echo NO)"

echo "##### DOCTOR #2 (after re-run) #####"
/bin/bash "\$SHARE/lib/doctor.sh" "$PROFILE"; echo "DOCTOR_EXIT2=\$?"
REMOTESCRIPT

set +e
vm_ssh "$REMOTE" 2>&1 | tee -a "$OUT"
set -e 2>/dev/null || true

echo
log_step "DOGFOOD SUMMARY"
grep -E 'DOCTOR_EXIT=|DOCTOR_EXIT2=|== [0-9]+ passed|PROBE:|IDEMP:' "$OUT" | sed 's/^/  /'
rc="$(grep -oE 'DOCTOR_EXIT2=[0-9]+' "$OUT" | tail -1 | cut -d= -f2)"; rc="${rc:-1}"
exit "$rc"

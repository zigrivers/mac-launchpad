#!/usr/bin/env bash
#
# scripts/test-in-vm.sh [profile]
#
# End-to-end test on a CLEAN macOS VM using Tart — no real Mac gets touched.
# Because the modules are plain idempotent bash, this exercises the real install
# path without an agent in the loop. It:
#   1. clones a fresh VM from a cirruslabs base image,
#   2. shares this repo into the VM,
#   3. runs bootstrap.sh (installs the agents; skips the git clone) then
#      install-profile.sh <profile> headlessly,
#   4. runs doctor.sh and reports pass/fail.
#
# Requires: tart (auto-installed) and sshpass (auto-installed) on the host.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

IMAGE="${TART_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}"
VM="${TART_VM:-launchpad-test}"
PROFILE="${1:-web-starter}"
VM_USER="${TART_VM_USER:-admin}"
VM_PASS="${TART_VM_PASS:-admin}"
SHARE_GUEST="/Volumes/My Shared Files/launchpad"
OUT="/tmp/launchpad-vm-${PROFILE}.log"

# --- host prerequisites -----------------------------------------------------
if ! have tart; then
  brew trust cirruslabs/cli >/dev/null 2>&1 || true
  brew install cirruslabs/cli/tart || die "could not install tart"
fi
if ! have sshpass; then
  brew trust hudochenkov/sshpass >/dev/null 2>&1 || true
  brew install hudochenkov/sshpass/sshpass >/dev/null 2>&1 || log_warn "could not install sshpass — SSH may prompt for a password"
fi

VM_PID=""
cleanup() {
  [ -n "$VM_PID" ] && kill "$VM_PID" >/dev/null 2>&1 || true
  tart stop "$VM" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_step "Pulling base image (cached if present)"
tart pull "$IMAGE" || log_warn "pull failed (continuing if image is cached)"

log_step "Cloning a fresh VM: $VM"
tart delete "$VM" >/dev/null 2>&1 || true
tart clone "$IMAGE" "$VM" || die "tart clone failed"

log_step "Booting VM (headless), sharing the repo read-only"
tart run "$VM" --no-graphics --dir=launchpad:"$ROOT":ro >/dev/null 2>&1 &
VM_PID=$!

log_info "Waiting for the VM to get an IP…"
ip="$(tart ip "$VM" --wait 180 2>/dev/null)"
[ -n "$ip" ] || die "VM never reported an IP"
log_ok "VM IP: $ip"

vm_ssh() {
  sshpass -p "$VM_PASS" ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$VM_USER@$ip" \
    "export PATH=\"\$HOME/.local/bin:/opt/homebrew/bin:\$PATH\"; $*"
}

log_info "Waiting for SSH…"
ok=0
for _ in $(seq 1 40); do
  if vm_ssh true 2>/dev/null; then ok=1; break; fi
  sleep 5
done
[ "$ok" = 1 ] || die "could not SSH into the VM"
log_ok "SSH up"

: > "$OUT"
log_step "Stage 0: bootstrap (agents + autonomy configs, no clone) — see $OUT"
vm_ssh "export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1; /bin/bash '$SHARE_GUEST/bootstrap.sh'" 2>&1 | tee -a "$OUT"

log_step "Stage 1: install profile '$PROFILE' headlessly — see $OUT"
vm_ssh "export LAUNCHPAD_NONINTERACTIVE=1; cd '$SHARE_GUEST' && /bin/bash scripts/install-profile.sh '$PROFILE'" 2>&1 | tee -a "$OUT"

log_step "Running doctor in the VM"
set +e
vm_ssh "cd '$SHARE_GUEST' && /bin/bash lib/doctor.sh '$PROFILE'" 2>&1 | tee -a "$OUT"
rc=${PIPESTATUS[0]}
set -e 2>/dev/null || true

echo
if [ "$rc" -eq 0 ]; then
  log_ok "VM TEST PASSED for profile '$PROFILE' (doctor green). Full log: $OUT"
else
  log_warn "VM TEST: doctor reported failures (rc=$rc) for '$PROFILE'. Review $OUT"
fi
exit "$rc"

#!/usr/bin/env bash
#
# dogfood/vm-probes.sh — boot a clean Tart VM and run dogfood/remote-probes.sh
# (lean install + corrected functional probes). Companion to vm-dogfood.sh; used
# to re-validate the probes that the full run couldn't (template runs, real
# secret blocking, zshrc idempotency). Never touches the host.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"

IMAGE="${TART_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}"
VM="${TART_VM:-launchpad-probes}"
VM_USER="${TART_VM_USER:-admin}"; VM_PASS="${TART_VM_PASS:-admin}"
SHARE_GUEST="/Volumes/My Shared Files/launchpad"
OUT="/tmp/launchpad-probes.log"
REMOTE_SCRIPT="${1:-dogfood/remote-probes.sh}"

have tart || { brew trust cirruslabs/cli >/dev/null 2>&1 || true; brew install cirruslabs/cli/tart || die "no tart"; }
have sshpass || { brew trust hudochenkov/sshpass >/dev/null 2>&1 || true; brew install hudochenkov/sshpass/sshpass >/dev/null 2>&1 || true; }

VM_PID=""; CTRL="/tmp/launchpad-ssh-${VM}.ctl"
cleanup() {
  ssh -o ControlPath="$CTRL" -O exit "$VM_USER@${ip:-127.0.0.1}" >/dev/null 2>&1 || true
  rm -f "$CTRL"; [ -n "$VM_PID" ] && kill "$VM_PID" >/dev/null 2>&1 || true
  tart stop "$VM" >/dev/null 2>&1 || true; tart delete "$VM" >/dev/null 2>&1 || true
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
log_step "Running $REMOTE_SCRIPT in the VM — streaming to $OUT"
set +e
vm_ssh "/bin/bash '$SHARE_GUEST/$REMOTE_SCRIPT'" 2>&1 | tee -a "$OUT"
set -e 2>/dev/null || true

echo
log_step "PROBE SUMMARY"
grep -E 'PROBE:|IDEMP:|GITLEAKS_|FOUND:|ZSHRC-DIFF' "$OUT" | sed 's/^/  /'
fails="$(grep -cE 'PROBE:[a-z_]+=FAIL' "$OUT" || true)"
exit "$fails"

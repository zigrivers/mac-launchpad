#!/usr/bin/env bash
#
# 12-containers — a lean container toolchain on OrbStack (the only engine; no
# Docker Desktop). OrbStack already ships the standard `docker` CLI, Compose v2,
# buildx, a GUI (container list, logs, a Files tab), `.orb.local` domains, and
# Kubernetes — so this module adds only what OrbStack does NOT cover: Dockerfile
# quality (hadolint), image slimming (dive), and a deploy path (fly).
#
# No GUI/TUI tools (OrbStack's GUI is better for non-technical users), no
# engine-switching, no Kubernetes tooling.
#
# Runs for app/backend/ML profiles — any profile that includes the web or ml
# area. Verified 2026-06-15.
#
# (Optional, intentionally NOT installed — OrbStack's GUI already covers
# visibility and most users won't need dev containers: `lazydocker` for a
# terminal container view, and `@devcontainers/cli` for reproducible dev envs.
# Add them by hand if you ever want them.)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "12 · Containers (OrbStack)"

# --- engine: OrbStack (standard docker CLI + Compose v2 + buildx + GUI) ------
brew_cask orbstack

# --- build plumbing: buildx ships with the engine (verify, don't install) ----
# The engine only responds once OrbStack has been launched once, so this is a
# best-effort check, not a hard requirement.
if docker buildx version >/dev/null 2>&1; then
  log_ok "docker buildx available ($(docker buildx version 2>/dev/null | head -1))"
else
  log_note "docker/buildx become available once OrbStack is running — open it once: open -a OrbStack"
fi

# --- Dockerfile quality + image slimming (the real value OrbStack lacks) -----
brew_install hadolint dive

# --- deploy on-ramp ---------------------------------------------------------
brew_install flyctl

# --- registry login + deploy (interactive — do these when you're ready) -----
log_note "Push images (interactive, one-time):"
log_note "  • Docker Hub:  docker login"
log_note "  • GitHub (ghcr.io):  gh auth refresh -s write:packages && gh auth token | docker login ghcr.io -u <you> --password-stdin"
log_note "Deploy a container app:  fly auth login  then  fly launch"
log_note "  (GCP users: Google Cloud Run is an alternative target, incl. for GPU workloads.)"
log_note "Project templates (multi-stage Dockerfile + Compose: app/Postgres/Redis) are in config/docker/."

log_ok "Container toolchain complete — engine: OrbStack (open it once to start Docker)"

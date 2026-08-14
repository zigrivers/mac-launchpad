# 12-containers — the container toolchain. Windows twin of modules/12-containers.sh.
#
# Windows notes (verified 2026-08-14):
#   * OrbStack is macOS-only, so the Windows engine is Docker Desktop (docker
#     CLI + Compose v2 + buildx + GUI). It must be launched once from the Start
#     menu to finish setup (it may ask to enable WSL 2 and log out/in).
#   * flyctl installs via the official PowerShell installer
#     (https://fly.io/docs/flyctl/install/: iwr https://fly.io/install.ps1 -useb | iex).
#   * SKIPPED on Windows v1: hadolint and dive (Dockerfile lint + image
#     slimming are a later add-on).
#
# Runs for app/backend/ML profiles — any profile that includes the web or ml
# area.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

Log-Step '12 · Containers (Docker Desktop)'

# --- engine: Docker Desktop (standard docker CLI + Compose v2 + buildx + GUI) -
# (OrbStack is macOS-only — Docker Desktop is the Windows engine.)
Winget-Install @('Docker.DockerDesktop')
Log-Note 'Launch Docker Desktop once from the Start menu to finish its setup (it may ask to enable WSL 2 and log out/in).'

# --- build plumbing: buildx ships with the engine (verify, don't install) -----
# The engine only responds once Docker Desktop has been launched, so this is a
# best-effort check, not a hard requirement.
docker buildx version >$null 2>&1
if ($LASTEXITCODE -eq 0) {
    Log-Ok "docker buildx available ($((docker buildx version 2>$null | Select-Object -First 1)))"
} else {
    Log-Note 'docker/buildx become available once Docker Desktop is running - open it once from the Start menu'
}

# (hadolint, dive: SKIPPED on Windows v1 — Dockerfile lint + image slimming are a later add-on.)

# --- deploy on-ramp -----------------------------------------------------------
Refresh-SessionPath
if (Have fly) {
    Log-Ok 'flyctl present'
} elseif (Have flyctl) {
    Log-Ok 'flyctl present'
} else {
    Log-Info 'installing flyctl (official installer)...'
    try {
        iwr https://fly.io/install.ps1 -useb | iex
        Refresh-SessionPath
        if ((Have fly) -or (Have flyctl)) { Log-Ok 'flyctl installed' }
        else { Log-Warn 'flyctl installer finished but fly is not on PATH yet (open a new window)' }
    } catch {
        Log-Warn "flyctl install failed: $($_.Exception.Message)"
    }
}

# --- registry login + deploy (interactive — do these when you're ready) -------
Log-Note 'Push images (interactive, one-time):'
Log-Note '  • Docker Hub:  docker login'
Log-Note '  • GitHub (ghcr.io):  gh auth refresh -s write:packages, then  gh auth token | docker login ghcr.io -u <you> --password-stdin'
Log-Note 'Deploy a container app:  fly auth login  then  fly launch'
Log-Note '  (GCP users: Google Cloud Run is an alternative target, incl. for GPU workloads.)'
Log-Note 'Project templates (multi-stage Dockerfile + Compose: app/Postgres/Redis) are in config/docker/.'

Log-Ok 'Container toolchain complete - engine: Docker Desktop (open it once to start Docker)'

# 15-testing — the testing layer. Windows twin of modules/15-testing.sh.
# Installs agent-browser (the agents' live browser, driven via the
# agent-browser skill from 06-skills) and pre-caches the Playwright browsers so
# every project shares them. Per-project test deps + CI come from
# config/testing/ templates the agents copy into a project.
#
# Windows notes (verified 2026-08-14):
#   * agent-browser is brew-only on macOS; on Windows it installs via
#     `npm install -g agent-browser` (`agent-browser install` then fetches
#     Chrome for Testing; idempotent).
#   * Playwright uses plain `npx playwright install` (--with-deps is
#     Linux-only); the cache lands in $env:LOCALAPPDATA\ms-playwright.
#   * SKIPPED on Windows v1: Maestro (the vendor installer is bash/macOS-
#     oriented; mobile e2e is a later add-on).
#
# Runs for app-building profiles (any profile that includes the web area).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

Log-Step '15 · Testing (agent-browser, Playwright cache)'

# Make sure Node is active for the npm/npx steps.
if (Have fnm) {
    fnm env --shell power-shell 2>$null | Out-String | Invoke-Expression
    fnm use default >> $env:LAUNCHPAD_LOG 2>&1
}
if (-not ((Have npm) -and (Have npx))) {
    Log-Warn 'npm/npx not on PATH - re-run 00-foundation, then this module'
}

# --- agent-browser: the agents' live browser (Chrome for Testing) -------------
if (Have npm) {
    if (Have agent-browser) {
        Log-Ok 'agent-browser CLI present'
    } else {
        npm install -g agent-browser >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Log-Ok 'agent-browser CLI installed' }
        else { Log-Warn "agent-browser install failed (see $env:LAUNCHPAD_LOG)" }
        Refresh-SessionPath
    }
    if (Have agent-browser) {
        # Downloads Chrome for Testing on first run; idempotent (reuses an
        # existing Chrome/Playwright browser if it finds one).
        agent-browser install >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Log-Ok 'agent-browser ready (Chrome for Testing)' }
        else { Log-Warn "agent-browser install had issues (see $env:LAUNCHPAD_LOG)" }
    }
}

# --- Playwright browser pre-cache (shared: $env:LOCALAPPDATA\ms-playwright) ---
if (Have npx) {
    Log-Info 'pre-caching Playwright browsers (shared by every project)...'
    npx -y playwright install >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) { Log-Ok 'Playwright browsers cached' }
    else { Log-Warn "Playwright browser pre-cache had issues (see $env:LAUNCHPAD_LOG)" }
}

# (Maestro: SKIPPED on Windows v1 — the vendor installer is bash/macOS-oriented;
#  mobile e2e is a later add-on. No PATH lines added for it.)

Log-Note 'Per-project test setup (Vitest/Playwright/axe/visual/CI) lives in config/testing/ - the agents copy it in.'
Log-Ok 'Testing layer complete'

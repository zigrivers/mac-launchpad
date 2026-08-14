# 10-web — the web/app stack: pnpm, the Vercel CLI, and the Stripe CLI.
# Windows twin of modules/10-web.sh.
#
# Windows notes (verified 2026-08-14):
#   * pnpm: corepack is deprecated (removed from Node 25+), so pnpm installs
#     via `npm install -g pnpm` instead.
#   * Supabase CLI has no winget package (supabase/cli#1611) — projects use
#     `npx supabase`, which already works via Node; doctor knows.
#   * SKIPPED on Windows v1: bun, postgresql@16, cloudflared, ngrok — Postgres
#     runs via Docker or `npx supabase` locally; tunnels are a later add-on.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

Log-Step '10 · Web / App stack'

# Make sure Node is active for the npm steps.
if (Have fnm) {
    fnm env --shell power-shell 2>$null | Out-String | Invoke-Expression
    fnm use default >> $env:LAUNCHPAD_LOG 2>&1
}
if (-not (Have npm)) {
    Log-Warn 'npm not on PATH - re-run 00-foundation, then this module'
}

# --- pnpm (npm global; corepack is deprecated and gone from Node 25+) ---------
if (Have npm) {
    if (Have pnpm) {
        Log-Ok "pnpm ready ($(pnpm --version 2>$null))"
    } else {
        npm install -g pnpm >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Log-Ok 'pnpm installed' }
        else { Log-Warn "pnpm install failed (see $env:LAUNCHPAD_LOG)" }
    }
}

# (bun: SKIPPED on Windows v1 — the installer is bash/macOS-oriented; pnpm covers it.)

# --- payments CLI (the container engine lives in 12-containers) ---------------
Winget-Install @('Stripe.StripeCli')
# (postgresql@16, cloudflared, ngrok: SKIPPED on Windows v1 — Postgres runs via
#  Docker or `npx supabase` locally; tunnels are a later add-on.)

# --- Supabase CLI: no winget package (supabase/cli#1611) ----------------------
Log-Note "Supabase CLI has no Windows installer - projects use 'npx supabase' (already works via Node)."

# --- Vercel CLI (npm global) --------------------------------------------------
if (Have npm) {
    if (Have vercel) {
        Log-Ok 'vercel CLI present'
    } else {
        npm install -g vercel >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Log-Ok 'vercel CLI installed' }
        else { Log-Warn 'vercel install failed' }
    }
}

Log-Note 'Next, when you need them (one-time, interactive):'
Log-Note '  • vercel:   vercel login'
Log-Note '  • supabase: npx supabase login'
Log-Note '  • Postgres: run it via Docker (see config/docker/) or npx supabase start'
Log-Note '  • Playwright browsers are pre-cached for all projects by the testing module (15-testing).'

Log-Ok 'Web stack complete'

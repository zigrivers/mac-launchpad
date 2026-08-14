# 09-dx — developer-experience niceties that make autonomous building pleasant
# for a non-technical user. Runs for every profile. Installs:
#   * Beekeeper Studio — a free GUI to SEE and edit your database (no SQL needed)
#   * Biome — consistent formatting + linting across every project
#   * the `launchpad` command (new / harden / doctor / update / notify)
# Windows twin of modules/09-dx.sh.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

Log-Step '09 · Developer experience'

# --- 1. a database GUI you can actually see -----------------------------------
Winget-Install @('beekeeper-studio.beekeeper-studio')

# --- 2. consistent formatting across every project ----------------------------
# Biome formats + lints every project identically. Homebrew-only on macOS; on
# Windows the npm CLI is the supported install (binary: `biome`).
if (Have npm) {
    if (Have biome) {
        Log-Ok 'Biome already installed'
    } else {
        npm install -g '@biomejs/biome' >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Refresh-SessionPath; Log-Ok 'installed Biome (npm)' }
        else { Log-Warn "Biome install failed (see $env:LAUNCHPAD_LOG)" }
    }
} else {
    Log-Warn 'npm not on PATH — 00-foundation installs Node; re-run this module after'
}

# --- 3. desktop notifications when long tasks finish --------------------------
# SKIPPED: terminal-notifier is macOS-only — `launchpad notify` uses a native
# Windows toast in windows\scripts\launchpad.ps1 instead.

# SKIPPED (macOS launchd): the daily spend-guardrail agent — the Windows
# scheduled-task twin is a later add-on.

# --- 5. put the `launchpad` command on PATH -----------------------------------
# A tiny .cmd shim dispatches into windows\scripts\launchpad.ps1
# (new | harden | doctor | update | notify).
$localBin = Join-Path $HOME '.local\bin'
Ensure-Dir $localBin
$shim = Join-Path $localBin 'launchpad.cmd'
$launchpadPs1 = Join-Path $script:LP_ROOT 'windows\scripts\launchpad.ps1'
# Use %USERPROFILE% instead of the literal home path: .cmd files are read in
# the console codepage, so a non-ASCII username in a hardcoded path would be
# mangled and break every `launchpad` call.
$shimTarget = $launchpadPs1
if ($shimTarget.StartsWith($HOME)) { $shimTarget = '%USERPROFILE%' + $shimTarget.Substring($HOME.Length) }
if ($shimTarget -match '[^\x00-\x7F]') {
    Log-Warn "the repo path contains non-ASCII characters ($shimTarget) - the 'launchpad' shim may not work; move the repo to an ASCII path"
}
$shimBody = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$shimTarget" %*
"@
Set-Content -Path $shim -Value $shimBody -Encoding ASCII
Log-Ok "installed 'launchpad' shim at $shim"

# Persist ~\.local\bin on the USER PATH so every new shell (and agent) finds it.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $userPath) { $userPath = '' }
if (($userPath -split ';') -notcontains $localBin) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$localBin", 'User')
    Log-Ok "added $localBin to the user PATH (new shells pick it up)"
} else {
    Log-Ok "$localBin already on the user PATH"
}
Refresh-SessionPath

Log-Ok "Developer experience ready: Beekeeper Studio, Biome, 'launchpad' command"

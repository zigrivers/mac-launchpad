# 08-safety — the safety net. Installs local secret-scanning (gitleaks) and the
# pre-commit framework, and wires a comprehensive GLOBAL gitignore so secrets
# are never even staged. Runs for every profile.
# Windows twin of modules/08-safety.sh.
#
# Why this matters: the people using this machine run three full-autonomy agents
# and can't read a leaked key. The defence is layered and LOCAL-FIRST:
#   1. global gitignore (here)         — secrets never get staged
#   2. gitleaks pre-commit hook         — a commit with a secret is refused
#   3. private GitHub repo per project  — off-machine backup (harden-project.sh)
#   4. GitHub push protection (bonus)   — only free on PUBLIC repos

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

Log-Step '08 · Safety net (secret scanning + backups)'

# --- 1. local secret scanning + the pre-commit framework --------------------
Winget-Install @('Gitleaks.Gitleaks')
# pre-commit has no winget package — it's a Python tool, installed via uv.
if (Have 'uv') {
    if (Have 'pre-commit') {
        Log-Ok 'pre-commit already installed'
    } else {
        uv tool install pre-commit >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Refresh-SessionPath; Log-Ok 'installed pre-commit (via uv)' }
        else { Log-Warn "pre-commit install failed (see $env:LAUNCHPAD_LOG)" }
    }
} else {
    Log-Warn 'uv not on PATH — 00-foundation installs it; re-run this module after'
}

# --- 2. global gitignore (git's core.excludesfile) --------------------------
# Applies to EVERY repo on this machine, so .env / *.key / SSH keys etc. can
# never be staged by accident. Per-project .gitignore files add to this.
$gitcfgDir = Join-Path $HOME '.config\git'
Ensure-Dir $gitcfgDir
$gitignoreGlobal = Join-Path $gitcfgDir 'ignore.global'
if (Test-Path $gitignoreGlobal) { Backup-File $gitignoreGlobal }
Copy-Item -Force (Join-Path $script:LP_ROOT 'config\safety\gitignore.global') $gitignoreGlobal
if (Have git) {
    # git understands forward slashes on Windows, so keep the path portable.
    $excludesPath = '~/.config/git/ignore.global'
    $current = git config --global --get core.excludesfile 2>$null
    if ($current -ne $excludesPath) {
        git config --global core.excludesfile $excludesPath
        Log-Ok 'wired global gitignore -> ~/.config/git/ignore.global (core.excludesfile)'
    } else {
        Log-Ok 'global gitignore already wired (core.excludesfile)'
    }
} else {
    Log-Warn 'git not on PATH — re-run this module after 00-foundation'
}

# SKIPPED (macOS-only flow): pre-warming the pre-commit hook cache needs a POSIX
# tmp-dir flow — the first project install warms the shared cache instead.
# SKIPPED: chmod +x on harden-project.sh — chmod is meaningless on NTFS.

Log-Note 'Secret defence is LOCAL-FIRST: the gitleaks pre-commit hook is the real'
Log-Note "safeguard. GitHub's server-side push protection is a bonus and is only"
Log-Note 'free on PUBLIC repos (free private repos cannot use it).'
Log-Ok 'Safety net ready: gitleaks + pre-commit + global gitignore'

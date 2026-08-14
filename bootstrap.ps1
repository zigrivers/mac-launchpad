# Mac Launchpad — Windows Stage 0 bootstrap.
# Run this ONCE in PowerShell on a fresh Windows PC (Win+X, then "Terminal" or
# "Windows PowerShell"):
#
#   irm https://raw.githubusercontent.com/zigrivers/mac-launchpad/main/bootstrap.ps1 | iex
#
# It lays the foundation (winget, Git, the three AI agents, Chrome) and clones
# the repo, then hands off to Claude Code for the real setup. It is
# self-contained: it does NOT depend on the cloned repo, so it works fetched
# straight from `irm`. Everything it does is idempotent — running it twice is
# safe. It must run on stock Windows PowerShell 5.1 (no pwsh-7-only syntax).

$ErrorActionPreference = 'Continue'

$LOG = Join-Path $HOME 'launchpad-setup.log'
try { Start-Transcript -Path $LOG -Append -ErrorAction SilentlyContinue | Out-Null } catch { }

# Overridable so forks / tests can point elsewhere.
if (-not $env:LAUNCHPAD_REPO) { $env:LAUNCHPAD_REPO = 'https://github.com/zigrivers/mac-launchpad.git' }
if (-not $env:LAUNCHPAD_DIR) { $env:LAUNCHPAD_DIR = Join-Path $HOME 'Developer\mac-launchpad' }

# --- minimal self-contained logging ------------------------------------------
function Say([string]$Msg)  { Write-Host ''; Write-Host '==>' -ForegroundColor Blue -NoNewline; Write-Host " $Msg" }
function Ok([string]$Msg)   { Write-Host '   ' -NoNewline; Write-Host ([char]0x2714) -ForegroundColor Green -NoNewline; Write-Host " $Msg" }
function Warn([string]$Msg) { Write-Host '   ' -NoNewline; Write-Host '!' -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }
function Die([string]$Msg)  {
    Write-Host '   ' -NoNewline; Write-Host ([char]0x2718) -ForegroundColor Red -NoNewline; Write-Host " $Msg"
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
function HaveCmd([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function RefreshPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
    foreach ($p in @((Join-Path $HOME '.local\bin'), (Join-Path $env:LOCALAPPDATA 'agy\bin'))) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
    }
}

Write-Host @'

  ===============================================================

    Mac Launchpad  (Windows edition)
    Turning a fresh Windows PC into a complete dev machine, with AI.

  ===============================================================

  What's happening: this sets up your PC for building software. It runs
  for a few minutes and prints a lot of text as it works — that's normal,
  and you don't need to do anything. A few things that help:

    - Stay plugged in to power if you can.
    - If Windows pops up "Do you want to allow this app to make changes?"
      click Yes. That's an installer asking permission — it's expected.
    - Leave this window open until it says it's finished.

'@

# --- 1. platform assertions ---------------------------------------------------
Say 'Checking your PC'
if ($env:OS -ne 'Windows_NT') { Die 'This script is for Windows only. On a Mac, use bootstrap.sh instead.' }
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 17763) { Die "Windows 10 version 1809 or newer is required (this PC reports build $build). Please update Windows first (Settings > Windows Update)." }
if (-not [Environment]::Is64BitOperatingSystem) { Die '64-bit Windows is required.' }
$osName = 'Windows 10'
if ($build -ge 22000) { $osName = 'Windows 11' }
Ok "$osName (build $build), 64-bit"

# --- 2. winget (the Windows package manager) ----------------------------------
Say 'winget (the Windows package manager)'
if (HaveCmd winget) {
    Ok 'already available'
} else {
    Warn 'winget not found - trying to register the App Installer...'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue } catch { }
    RefreshPath
    if (-not (HaveCmd winget)) {
        Die 'winget is missing. Install "App Installer" from the Microsoft Store (https://apps.microsoft.com/detail/9nblggh4nns1), then run this command again.'
    }
    Ok 'winget registered'
}

function WingetInstall([string]$Id, [string]$Label) {
    winget list --id $Id -e --accept-source-agreements 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "$Label already installed"; return }
    Write-Host "   installing $Label..."
    winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Ok "$Label installed" } else { Warn "$Label install returned an error (see $LOG)" }
    RefreshPath
}

# --- 3. Git (needed to download the setup files; also gives the agents a
#        proper shell to work with via Git Bash) --------------------------------
Say 'Git (version control - the save-point system)'
WingetInstall 'Git.Git' 'Git'
RefreshPath
if (-not (HaveCmd git)) { Warn 'git is not on PATH yet - if the next steps fail, close this window, open a new PowerShell window, and run the command again.' }

# --- 4. The three AI agents (native installers, auto-updating) -----------------
Say 'Claude Code'
if (HaveCmd claude) {
    Ok "already installed ($((Get-Command claude).Source))"
} else {
    try { irm https://claude.ai/install.ps1 | iex } catch { Warn "Claude installer returned an error (see $LOG)." }
    RefreshPath
}
if (HaveCmd claude) { Ok 'claude on PATH' }

Say 'Codex (OpenAI)'
if (HaveCmd codex) {
    Ok "already installed ($((Get-Command codex).Source))"
} else {
    try { irm https://chatgpt.com/codex/install.ps1 | iex } catch { Warn "Codex installer returned an error (see $LOG)." }
    RefreshPath
}
if (HaveCmd codex) { Ok 'codex on PATH' }

Say 'Antigravity CLI (agy)'
if (HaveCmd agy) {
    Ok "already installed ($((Get-Command agy).Source))"
} else {
    try { irm https://antigravity.google/cli/install.ps1 | iex } catch { Warn "Antigravity installer returned an error (see $LOG)." }
    RefreshPath
}
if (HaveCmd agy) { Ok 'agy on PATH' }

Say 'Google Chrome (Antigravity uses it for sign-in + browser tools)'
WingetInstall 'Google.Chrome' 'Google Chrome'

# --- 5. Pre-seed full-autonomy configs so Stage 1 runs unattended --------------
# These mirror config/agents/* in the repo. windows/modules/05-agents.ps1
# reconciles them to the repo's authoritative copies (and adds MCP servers)
# after the clone. We only write them if absent, so an existing config is
# never clobbered.
Say 'Pre-configuring the agents for unattended setup'
$claudeDir = Join-Path $HOME '.claude'
$codexDir  = Join-Path $HOME '.codex'
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
if (-not (Test-Path $codexDir))  { New-Item -ItemType Directory -Path $codexDir -Force | Out-Null }
$claudeSettings = Join-Path $claudeDir 'settings.json'
if (-not (Test-Path $claudeSettings)) {
    @'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "includeCoAuthoredBy": true,
  "cleanupPeriodDays": 30
}
'@ | Set-Content -Path $claudeSettings -Encoding UTF8
    Ok 'wrote ~\.claude\settings.json (full autonomy)'
} else {
    Ok 'Claude settings already present (~\.claude\settings.json)'
}
$codexConfig = Join-Path $codexDir 'config.toml'
if (-not (Test-Path $codexConfig)) {
    @'
approval_policy = "never"
sandbox_mode    = "danger-full-access"
'@ | Set-Content -Path $codexConfig -Encoding UTF8
    Ok 'wrote ~\.codex\config.toml (full autonomy)'
} else {
    Ok 'Codex config already present (~\.codex\config.toml)'
}

# --- 6. Clone the repo ---------------------------------------------------------
Say 'Getting the Launchpad setup files'
$devDir = Join-Path $HOME 'Developer'
if (-not (Test-Path $devDir)) { New-Item -ItemType Directory -Path $devDir -Force | Out-Null }
if ($env:LAUNCHPAD_SKIP_CLONE -eq '1') {
    Ok 'skipping clone (LAUNCHPAD_SKIP_CLONE=1)'
} elseif (Test-Path (Join-Path $env:LAUNCHPAD_DIR '.git')) {
    git -C $env:LAUNCHPAD_DIR pull --ff-only 2>$null | Out-Null
    Ok "updated $($env:LAUNCHPAD_DIR)"
} else {
    if (-not (HaveCmd git)) { Die "git is not available, so the setup files can't be downloaded. Close this window, open a NEW PowerShell window, and run the command again." }
    # Retry the clone a few times: a transient network blip here is the #1
    # reason a run ends with the agents installed but the repo missing.
    $cloned = $false
    for ($n = 1; $n -le 3; $n++) {
        git clone --depth 1 $env:LAUNCHPAD_REPO $env:LAUNCHPAD_DIR
        if ($LASTEXITCODE -eq 0) { $cloned = $true; break }
        Warn "Download failed (attempt $n of 3) - retrying in 5s..."
        if (Test-Path $env:LAUNCHPAD_DIR) { Remove-Item -Recurse -Force $env:LAUNCHPAD_DIR -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 5
    }
    if ($cloned) { Ok "cloned to $($env:LAUNCHPAD_DIR)" }
    else { Die "Could not download the setup files after 3 tries. Check your internet, then run this command again - it picks up where it left off. (See $LOG.)" }
}

# --- 7. Hand-off ---------------------------------------------------------------
Write-Host ''
Write-Host 'Foundation ready.' -ForegroundColor Green
Write-Host @"

First, CLOSE this window and open a NEW PowerShell window (Win+X, then
"Terminal" or "Windows PowerShell") so the tools just installed are ready
to use. Do everything below in that new window.

Three quick logins:

  1. Run  claude  and sign in   (needs your Claude Pro account)
  2. Run  codex   and choose "Sign in with ChatGPT"  (needs your ChatGPT account)
  3. Run  agy     and sign in with Google   (needs a Gmail / Gemini account)

First time you run claude: it asks you to pick a theme - just press Enter -
then opens your browser to sign in. If no browser opens, press  c  to copy
the link, open it yourself, sign in, and paste the code it gives you back
here. If claude shows a red "Bypass Permissions" warning, choose
"2. Yes, I accept" so it can set everything up for you without stopping at
every step.

After each login, type  /exit  (or press Ctrl-C twice) to come back here
before starting the next one.

Then start the full setup - in that same window run:

  cd ~\Developer\mac-launchpad
  claude

and say:  "Follow CLAUDE.md and set me up for everything."
(swap "everything" for web-starter, full-stack, indie-game, or ml-lab to install less.)

Tip: your projects will be backed up to private GitHub repos as you work -
that's your safety net. Setup log: $LOG

"@
try { Stop-Transcript | Out-Null } catch { }

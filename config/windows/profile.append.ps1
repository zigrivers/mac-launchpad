# This block is managed by Launchpad (Windows). Re-running the installer
# replaces it in place (it never duplicates). Edit above or below the markers
# to customise. It must work in Windows PowerShell 5.1 AND PowerShell 7.

# --- PATH: user-local bins (claude, uv tools, agy) ---
foreach ($lpBin in @((Join-Path $HOME '.local\bin'), (Join-Path $env:LOCALAPPDATA 'agy\bin'))) {
    if ((Test-Path $lpBin) -and ($env:Path -notlike "*$lpBin*")) { $env:Path = "$lpBin;$env:Path" }
}

# --- fnm (fast Node version manager) ---
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell power-shell | Out-String | Invoke-Expression
}

# --- Starship prompt ---
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

# --- Quality-of-life helpers (functions, since PS aliases can't carry args) ---
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ll { eza -lah --group-directories-first --git @args }
    function lt { eza --tree --level=2 @args }
} else {
    function ll { Get-ChildItem -Force @args }
}
function g  { git @args }
function gs { git status -sb @args }
function dev { Set-Location (Join-Path $HOME 'Developer') }
function reload { . $PROFILE }
# See your Claude Code token usage + estimated cost (reads local logs, no key).
function ccusage { npx -y ccusage@latest @args }

# --- new-project safety net: `mkproj name` makes a safe, backed-up project ---
# Creates ~\Developer\<name>, cds into it, and runs the full safety flow: git +
# a secret-scanning pre-commit hook + a PRIVATE GitHub backup (when you're
# logged in to GitHub). For a ready-to-run starter template instead of an empty
# folder, use:  launchpad new
function mkproj {
    param([string]$Name)
    if (-not $Name) { Write-Host 'usage: mkproj <name>'; return }
    $dir = Join-Path (Join-Path $HOME 'Developer') $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Location $dir
    $lp = if ($env:LAUNCHPAD_DIR) { $env:LAUNCHPAD_DIR } else { Join-Path $HOME 'Developer\mac-launchpad' }
    $harden = Join-Path $lp 'scripts\harden-project.sh'
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    $bash = $null
    if ($gitCmd) {
        $candidate = Join-Path (Split-Path (Split-Path $gitCmd.Source -Parent) -Parent) 'bin\bash.exe'
        if (Test-Path $candidate) { $bash = $candidate }
    }
    if ($bash -and (Test-Path $harden)) {
        # The safety logic is shared with macOS and runs through Git Bash,
        # which understands C:/-style paths.
        & $bash ($harden -replace '\\', '/') ($dir -replace '\\', '/')
    } elseif (-not (Test-Path (Join-Path $dir '.git'))) {
        git init -q
        "node_modules/`n.env`ndist/`nbuild/`nThumbs.db" | Set-Content -Path (Join-Path $dir '.gitignore') -Encoding UTF8
        git add -A; git commit -q -m 'init: project checkpoint' 2>$null
        Write-Host ([char]0x2714 + " $dir created and git-initialised (a checkpoint to revert to).")
        # Be honest about what the fallback could NOT set up.
        Write-Host '! Setup files not found, so the secret-scan hook and the private GitHub backup were SKIPPED.' -ForegroundColor Yellow
        Write-Host '  Fix: make sure Git for Windows is installed and the launchpad repo is at ~\Developer\mac-launchpad, then run:  launchpad harden .' -ForegroundColor Yellow
    }
}

# --- Editor defaults ---
if (Get-Command code -ErrorAction SilentlyContinue) {
    $env:EDITOR = 'code --wait'
    $env:VISUAL = $env:EDITOR
}

# --- Android SDK (exported only if the mobile module installed it) ---
$lpAndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
if (Test-Path $lpAndroidSdk) {
    $env:ANDROID_HOME = $lpAndroidSdk
    foreach ($p in @("$lpAndroidSdk\platform-tools", "$lpAndroidSdk\emulator")) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
    }
}

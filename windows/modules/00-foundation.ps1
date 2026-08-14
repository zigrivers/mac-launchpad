# 00-foundation — git, GitHub CLI, Node (via fnm), the modern CLI toolkit, the
# coding font, and the ~\Developer workspace. Runs for every profile.
# Windows twin of modules/00-foundation.sh (winget instead of Homebrew).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Log-Step '00 · Foundation'

# --- git + the CLI toolkit ----------------------------------------------------
# (tree/wget/htop are built into Windows or covered by eza/curl/Task Manager;
#  mas is Mac-App-Store-only; 1password-cli comes with a later add-on.)
Winget-Install @(
    'Git.Git', 'GitHub.cli',
    'BurntSushi.ripgrep.MSVC', 'sharkdp.fd', 'sharkdp.bat', 'eza-community.eza',
    'junegunn.fzf', 'jqlang.jq', 'Starship.Starship', 'Schniz.fnm',
    'astral-sh.uv'
)

# --- media tools: the agents constantly reach for these for image/video work --
Winget-Install @('Gyan.FFmpeg', 'ImageMagick.ImageMagick')

# --- coding font --------------------------------------------------------------
Winget-Install @('DEVCOM.JetBrainsMonoNerdFont')

# --- shared git config (non-destructively included from ~\.gitconfig) ---------
$gitcfgDir = Join-Path $HOME '.config\git'
Ensure-Dir $gitcfgDir
Copy-Item -Force (Join-Path $script:LP_ROOT 'config\git\gitconfig') (Join-Path $gitcfgDir 'launchpad.gitconfig')
$ignoreFile = Join-Path $gitcfgDir 'ignore'
if (-not (Test-Path $ignoreFile)) {
    Write-LpFile $ignoreFile @'
.DS_Store
.env
.env.local
node_modules/
dist/
build/
.venv/
__pycache__/
*.log
Thumbs.db
'@
}
if (Have git) {
    # git understands forward slashes everywhere, so keep the include portable.
    $includePath = '~/.config/git/launchpad.gitconfig'
    $existing = @(git config --global --get-all include.path 2>$null)
    if ($existing -notcontains $includePath) {
        git config --global --add include.path $includePath
        Log-Ok 'linked shared git config via ~\.gitconfig include'
    } else {
        Log-Ok 'shared git config already included'
    }
    # Set an identity only if none exists yet (derive from GitHub; never overwrite).
    git config --global user.name 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $ghname = ''
        if (Have gh) { $ghname = (gh api user --jq .login 2>$null) }
        if ($ghname) {
            git config --global user.name $ghname
            git config --global user.email "$ghname@users.noreply.github.com"
            Log-Ok "set git identity to '$ghname' (change with: git config --global user.email you@example.com)"
        } else {
            Log-Note 'git identity not set yet - will be set once GitHub is authenticated'
        }
    }
} else {
    Log-Warn 'git not on PATH - close this window and re-run in a new one'
}

# --- GitHub authentication ----------------------------------------------------
if (Have gh) {
    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Log-Ok 'GitHub CLI already authenticated'
    } elseif (Is-Interactive) {
        Log-Info 'Opening GitHub login - choose HTTPS and log in via the browser.'
        gh auth login
        if ($LASTEXITCODE -ne 0) { Log-Warn "gh auth login did not complete; re-run later with 'gh auth login'" }
    } else {
        Log-Warn "GitHub not authenticated and running non-interactively - skipping (run 'gh auth login' later)"
    }
}

# --- Node via fnm (LTS, set as default) ---------------------------------------
if (Have fnm) {
    fnm env --shell power-shell 2>$null | Out-String | Invoke-Expression
    fnm install --lts >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) {
        $ltsVer = (fnm ls 2>$null | Select-String -Pattern 'v\d+\.\d+\.\d+' -AllMatches |
                   ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } |
                   Sort-Object { [version]($_ -replace '^v', '') } | Select-Object -Last 1)
        if ($ltsVer) {
            fnm default $ltsVer >> $env:LAUNCHPAD_LOG 2>&1
            fnm use $ltsVer >> $env:LAUNCHPAD_LOG 2>&1
            Log-Ok "Node $ltsVer (LTS) installed and set as default"
        }
    } else {
        Log-Warn "fnm could not install Node LTS (see $env:LAUNCHPAD_LOG)"
    }
} else {
    Log-Warn 'fnm not on PATH yet - Node will be installed on the next run'
}

# --- Antigravity CLI (agy) — third core agent, installed for every profile ----
Refresh-SessionPath
if (Have agy) {
    Log-Ok "Antigravity CLI present ($((Get-Command agy).Source))"
} else {
    Log-Info 'installing Antigravity CLI (agy)...'
    try {
        irm https://antigravity.google/cli/install.ps1 | iex
        Refresh-SessionPath
        if (Have agy) { Log-Ok 'agy installed' } else { Log-Warn 'agy installer finished but agy is not on PATH yet' }
    } catch {
        Log-Warn "agy install failed: $($_.Exception.Message)"
    }
}
# Google Chrome — Antigravity uses it for Google sign-in + its browser tools.
Winget-Install @('Google.Chrome')

# --- workspace ----------------------------------------------------------------
Ensure-Dir $script:DEVELOPER_DIR
$envTemplate = Join-Path $script:DEVELOPER_DIR '.env.template'
if (-not (Test-Path $envTemplate)) {
    Write-LpFile $envTemplate @'
# Copy this to ".env" inside a project and fill in real values.
# NEVER commit a real .env file — it's git-ignored for you.
#
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
# DATABASE_URL=
# SUPABASE_URL=
# SUPABASE_ANON_KEY=
'@
    Log-Ok "created $envTemplate"
}

Log-Ok 'Foundation complete'

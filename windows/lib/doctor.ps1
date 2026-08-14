# windows/lib/doctor.ps1 [profile]
#
# The Windows twin of lib/doctor.sh. Green/red health check. RED = something
# the installer should have produced and didn't -> exit non-zero so the
# orchestrator fixes it and re-runs. YELLOW = needs a human (sign-ins) or a
# GUI step (Docker Desktop first launch, Android Studio wizard) - reported,
# but not a hard failure. If a profile is given, only that profile's
# toolchains are checked as hard requirements.

param([string]$ProfileName = '')

$ErrorActionPreference = 'Continue'
$env:LP_QUIET = '1'
. (Join-Path $PSScriptRoot 'common.ps1')
Refresh-SessionPath

$script:Pass = 0; $script:Fail = 0; $script:Warn = 0

function Hdr([string]$Title) { Write-Host ''; Write-Host $Title -ForegroundColor White }
function ChkOk([string]$Label) { Write-Host '   ' -NoNewline; Write-Host ([char]0x2714) -ForegroundColor Green -NoNewline; Write-Host " $Label"; $script:Pass++ }
function ChkNo([string]$Label) { Write-Host '   ' -NoNewline; Write-Host ([char]0x2718) -ForegroundColor Red -NoNewline; Write-Host " $Label"; $script:Fail++ }
function ChkWn([string]$Label) { Write-Host '   ' -NoNewline; Write-Host '!' -ForegroundColor Yellow -NoNewline; Write-Host " $Label"; $script:Warn++ }

# Check "label" { expression }  -> red on failure (hard)
# Softck "label" { expression } -> yellow on failure (needs human/GUI)
function Check([string]$Label, [scriptblock]$Test) {
    $ok = $false
    try { $ok = [bool](& $Test 2>$null) } catch { $ok = $false }
    if ($ok) { ChkOk $Label } else { ChkNo $Label }
}
function Softck([string]$Label, [scriptblock]$Test) {
    $ok = $false
    try { $ok = [bool](& $Test 2>$null) } catch { $ok = $false }
    if ($ok) { ChkOk $Label } else { ChkWn $Label }
}
function CmdOk([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function ExitOk([scriptblock]$Cmd) { & $Cmd | Out-Null; return ($LASTEXITCODE -eq 0) }
function FileHas([string]$Path, [string]$Pattern) {
    return ((Test-Path $Path) -and ((Get-Content $Path -Raw -ErrorAction SilentlyContinue) -match $Pattern))
}

# Which areas are in scope?
$areas = @()
if ($ProfileName) {
    $pf = Join-Path $script:LP_ROOT "profiles\$ProfileName.yaml"
    if (Test-Path $pf) {
        foreach ($line in (Get-Content $pf)) {
            if ($line -match '^\s*-\s+([A-Za-z]+)') { $areas += $Matches[1].ToLower() }
        }
    }
}
function AreaActive([string]$Area) {
    if (-not $ProfileName) { return $true }   # no profile -> check everything
    return ($areas -contains $Area)
}

Write-Host '== Launchpad doctor (Windows) ==' -NoNewline
if ($ProfileName) { Write-Host "  (profile: $ProfileName)" -NoNewline }
Write-Host ''

$psProfilePath = "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$ps7ProfilePath = "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"

Hdr 'Foundation'
Check 'winget (package manager)'        { CmdOk winget }
Check 'git'                             { CmdOk git }
Check 'Git Bash (for project scripts)'  { $null -ne (Get-GitBash) }
Check 'GitHub CLI (gh)'                 { CmdOk gh }
Softck 'GitHub authenticated'           { ExitOk { gh auth status } }
Check 'fnm (Node version manager)'      { CmdOk fnm }
Check 'Node'                            { CmdOk node }
Check 'ripgrep / fd / bat / eza / fzf / jq' { (CmdOk rg) -and (CmdOk fd) -and (CmdOk bat) -and (CmdOk eza) -and (CmdOk fzf) -and (CmdOk jq) }
Check 'uv (Python tool runner)'         { CmdOk uv }
Check 'media: ffmpeg'                   { CmdOk ffmpeg }
Check 'media: ImageMagick (magick)'     { CmdOk magick }

Hdr 'Shell & terminal'
Check 'PowerShell profile launchpad block' { (FileHas $ps7ProfilePath 'launchpad \(profile\)') -or (FileHas $psProfilePath 'launchpad \(profile\)') }
Check 'Starship installed'              { CmdOk starship }
Check 'Starship config'                 { Test-Path "$HOME\.config\starship.toml" }
Check 'JetBrainsMono Nerd Font'         { Winget-Installed 'DEVCOM.JetBrainsMonoNerdFont' }
Check 'Windows Terminal'                { Winget-Installed 'Microsoft.WindowsTerminal' }
Check 'PowerShell 7 (pwsh)'             { CmdOk pwsh }

Hdr 'Editors'
Check 'VS Code (code)'                  { CmdOk code }
Softck 'Claude Code extension (VS Code)' { (code --list-extensions 2>$null) -match 'anthropic.claude-code' }
Softck 'Codex extension (VS Code)'       { (code --list-extensions 2>$null) -match 'openai.chatgpt' }

Hdr 'AI agents'
Check 'claude on PATH'                  { CmdOk claude }
Check 'codex on PATH'                   { CmdOk codex }
Check 'agy (Antigravity) on PATH'       { CmdOk agy }
Check 'Google Chrome (for agy)'         { Winget-Installed 'Google.Chrome' }
Check 'Claude full-autonomy setting'    { FileHas "$HOME\.claude\settings.json" 'bypassPermissions' }
Check 'Codex full-autonomy setting'     { FileHas "$HOME\.codex\config.toml" 'approval_policy\s*=\s*"never"' }
Check 'agy autonomy (profile function)' { (FileHas $ps7ProfilePath 'dangerously-skip-permissions') -or (FileHas $psProfilePath 'dangerously-skip-permissions') }
Check 'Shared house-rules (Claude)'     { Test-Path "$HOME\.claude\CLAUDE.md" }
Check 'Shared house-rules (Codex)'      { Test-Path "$HOME\.codex\AGENTS.md" }
Check 'Shared house-rules (Antigravity)' { Test-Path "$HOME\.gemini\AGENTS.md" }
Softck 'Claude authenticated'           { Test-Path "$HOME\.claude\.credentials.json" }
foreach ($s in @('context7', 'playwright', 'filesystem')) {
    # $s resolves at call time via dynamic scoping - Check runs the block synchronously.
    Check "Claude MCP: $s (configured)"  { ExitOk { claude mcp get $s } }
    Check "Codex MCP: $s (configured)"   { FileHas "$HOME\.codex\config.toml" "\[mcp_servers.$s\]" }
}
Softck 'Claude MCP: github (needs gh login)' { ExitOk { claude mcp get github } }
Check 'Codex MCP: github (configured)'  { FileHas "$HOME\.codex\config.toml" '\[mcp_servers.github\]' }
Check 'Antigravity MCP (configured)'    { FileHas "$HOME\.gemini\antigravity-cli\mcp_config.json" 'context7' }
Check 'here.now skill (Claude)'         { Test-Path "$HOME\.claude\skills\here-now\SKILL.md" }
Check 'here.now skill (Codex)'          { Test-Path "$HOME\.agents\skills\here-now\SKILL.md" }
Check 'here.now skill (Antigravity)'    { Test-Path "$HOME\.gemini\antigravity-cli\skills\here-now\SKILL.md" }

Hdr 'Skills & workflow'
Check 'Superpowers (Claude Code)'       { FileHas "$HOME\.claude\settings.json" 'superpowers@claude-plugins-official' }
Check 'Superpowers skills (Codex + agy)' { Test-Path "$HOME\.agents\skills\using-superpowers" }
Check 'agent-browser skill (shared)'    { Test-Path "$HOME\.agents\skills\agent-browser" }
Check 'design skills (frontend-design + web-design-guidelines)' { (Test-Path "$HOME\.agents\skills\frontend-design") -and (Test-Path "$HOME\.agents\skills\web-design-guidelines") }
Check 'document skills (pdf/docx/pptx/xlsx)' { (Test-Path "$HOME\.agents\skills\pdf") -and (Test-Path "$HOME\.agents\skills\docx") -and (Test-Path "$HOME\.agents\skills\pptx") -and (Test-Path "$HOME\.agents\skills\xlsx") }

Hdr 'Safety net'
Check 'gitleaks (secret scanner)'       { CmdOk gitleaks }
Check 'pre-commit framework'            { CmdOk pre-commit }
Check 'global gitignore (core.excludesfile)' {
    $f = git config --global --get core.excludesfile 2>$null
    ($f) -and (Test-Path ($f -replace '^~', $HOME))
}
if (ExitOk { gh auth status }) {
    ChkOk 'GitHub backup ready - new projects get a private repo'
} else {
    ChkWn "Private GitHub backups need 'gh auth login' (projects stay local until then)"
    $script:Warn--   # informational
}

Hdr 'Developer experience'
Check 'Biome formatter'                 { CmdOk biome }
Check 'Beekeeper Studio (database GUI)' { Winget-Installed 'beekeeper-studio.beekeeper-studio' }
Check 'launchpad command (on PATH)'     { CmdOk launchpad }

if (AreaActive 'web') {
    Hdr 'Web stack'
    Check 'pnpm'                        { CmdOk pnpm }
    Check 'Vercel CLI'                  { CmdOk vercel }
    Check 'Stripe CLI'                  { CmdOk stripe }
    ChkWn 'Supabase CLI has no Windows installer - projects use "npx supabase" (already works via Node)'
    $script:Warn--   # informational

    Hdr 'Testing layer'
    Check 'agent-browser CLI'           { CmdOk agent-browser }
    Check 'Playwright browsers cached'  { (Test-Path "$env:LOCALAPPDATA\ms-playwright") -and ((Get-ChildItem "$env:LOCALAPPDATA\ms-playwright" -ErrorAction SilentlyContinue) -match 'chromium') }
}

if ((AreaActive 'web') -or (AreaActive 'ml')) {
    Hdr 'Containers (Docker Desktop)'
    Check 'Docker Desktop installed'    { Winget-Installed 'Docker.DockerDesktop' }
    Softck 'Docker engine responds'     { ExitOk { docker version } }
    ChkWn 'Docker needs Docker Desktop running - open it once from the Start menu to finish its setup (it may ask to enable WSL 2).'
    $script:Warn--   # informational
}

if (AreaActive 'mobile') {
    Hdr 'Mobile stack (Android - iOS apps need a Mac or a cloud build)'
    Check 'Temurin JDK (java)'          { CmdOk java }
    Check 'Android Studio'              { Winget-Installed 'Google.AndroidStudio' }
    Softck 'Android SDK (after first run)' { Test-Path "$env:LOCALAPPDATA\Android\Sdk" }
}

if (AreaActive 'games') {
    Hdr 'Games stack'
    Check 'Godot'                       { Winget-Installed 'GodotEngine.GodotEngine' }
    Check 'Unity Hub'                   { Winget-Installed 'Unity.UnityHub' }
}

if (AreaActive 'ml') {
    Hdr 'ML stack'
    Check 'uv'                          { CmdOk uv }
    Check 'Ollama'                      { CmdOk ollama }
    Check 'LM Studio'                   { Winget-Installed 'ElementLabs.LMStudio' }
    Check 'JupyterLab'                  { (CmdOk jupyter-lab) -or (CmdOk jupyter) }
    Softck 'ml-lab Python env (torch)'  { Test-Path "$script:DEVELOPER_DIR\ml-lab\.venv\Scripts\python.exe" }
}

Write-Host ''
Write-Host "== $script:Pass passed, $script:Fail failed, $script:Warn need attention ==" -ForegroundColor White
if ($script:Warn -gt 0) {
    Write-Host '(! items usually just need a sign-in or a one-time GUI step.)' -ForegroundColor DarkGray
}
if ($script:Fail -gt 0) {
    Write-Host "$([char]0x2718) $script:Fail check(s) failed - see red lines above." -ForegroundColor Red
    exit 1
}
Write-Host "$([char]0x2714) All required checks passed." -ForegroundColor Green
exit 0

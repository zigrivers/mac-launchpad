# 05-agents — the high-value module, Windows twin of modules/05-agents.sh.
# Configures Claude Code + Codex for full autonomy, gives all three agents one
# shared house-rules file, and wires up the same five MCP servers. Runs for
# every profile.
#
# Windows notes (verified 2026-08-14):
#   * Config paths are the same shapes: ~\.claude\settings.json,
#     ~\.codex\config.toml, ~\.gemini\antigravity-cli\mcp_config.json.
#   * npx is npx.cmd on Windows, so stdio MCP servers are registered through
#     `cmd /c npx ...` (claude-code#4158).
#   * Symlinks need admin or Developer Mode on Windows — we try, then fall
#     back to a copy (05 re-syncs the copy on every run, so it tracks the repo).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

Log-Step '05 · AI Agents (Claude Code + Codex + Antigravity)'

Ensure-Dir (Join-Path $HOME '.claude')
Ensure-Dir (Join-Path $HOME '.codex')

# --- 1. Full autonomy: Claude settings (deep-merged, never clobbered) ---------
$claudeSettings = Join-Path $HOME '.claude\settings.json'
$repoSettings = Get-Content (Join-Path $script:LP_ROOT 'config\agents\claude.settings.json') -Raw | ConvertFrom-Json
if (Merge-JsonFile -File $claudeSettings -Overrides (ConvertTo-LpHashtable $repoSettings)) {
    Log-Ok 'merged full autonomy into ~\.claude\settings.json'
}

# --- 2. Full autonomy: Codex config (ensure keys live above any [table]) ------
$codexCfg = Join-Path $HOME '.codex\config.toml'
if (-not (Test-Path $codexCfg)) {
    Copy-Item (Join-Path $script:LP_ROOT 'config\agents\codex.config.toml') $codexCfg
}
function Ensure-CodexKey([string]$Key, [string]$Line) {
    $content = Get-Content $codexCfg -Raw
    if ($content -notmatch "(?m)^\s*$Key\s*=") {
        Backup-File $codexCfg
        Set-Content -Path $codexCfg -Value ($Line + "`n" + $content) -Encoding UTF8
        Log-Ok "set $Key in ~\.codex\config.toml"
    } else {
        Log-Ok "$Key already set in ~\.codex\config.toml"
    }
}
Ensure-CodexKey 'approval_policy' 'approval_policy = "never"'
Ensure-CodexKey 'sandbox_mode'    'sandbox_mode    = "danger-full-access"'

# --- 3. One shared house-rules file for all three agents ----------------------
# Symlink when Windows allows it (Developer Mode / admin); otherwise copy —
# and refresh the copy on every run so it tracks the repo.
function Link-HouseRules([string]$Target, [string]$Link) {
    Ensure-Dir (Split-Path $Link -Parent)
    $item = Get-Item $Link -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'SymbolicLink' -and $item.Target -eq $Target) {
        Log-Ok "symlink ok: $Link"
        return
    }
    if (Test-Path $Link) { Backup-File $Link; Remove-Item $Link -Force }
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -ErrorAction Stop | Out-Null
        Log-Ok "linked $Link -> $Target"
    } catch {
        Copy-Item -Force $Target $Link
        Log-Ok "copied house-rules to $Link (symlinks need Developer Mode; a copy works the same and re-syncs each run)"
    }
}
$rules = Join-Path $script:LP_ROOT 'config\agents\AGENTS.md'
Link-HouseRules $rules (Join-Path $HOME '.claude\CLAUDE.md')
Link-HouseRules $rules (Join-Path $HOME '.codex\AGENTS.md')
Link-HouseRules $rules (Join-Path $HOME '.gemini\AGENTS.md')
Link-HouseRules $rules (Join-Path $HOME '.gemini\GEMINI.md')

# --- 4. Agent env in the PowerShell profile (GitHub token for the GitHub MCP) -
$agentBlock = @'
# GitHub token for the GitHub MCP server. Re-evaluated each shell, so it
# stays valid as long as `gh` is logged in. No static secret on disk.
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $env:GITHUB_PAT_TOKEN = (gh auth token 2>$null)
}

# Antigravity CLI: full autonomy by default for interactive sessions (matches
# Claude Code + Codex). Subcommands like `agy update` pass through untouched.
# Want permission prompts back? Run the binary directly:  & (Get-Command agy -CommandType Application).Source
function agy {
    $agyBin = (Get-Command agy -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $agyBin) { Write-Host 'agy is not installed'; return }
    $first = ''
    if ($args.Count -gt 0) { $first = [string]$args[0] }
    switch ($first) {
        { $_ -in @('', '-p', '--print', '--prompt', '-i', '--prompt-interactive', '-c', '--continue', '--conversation', '--model', '--add-dir') } {
            & $agyBin --dangerously-skip-permissions @args
        }
        default { & $agyBin @args }
    }
}
'@
foreach ($envName in @('CONTEXT7_API_KEY', 'HERENOW_API_KEY', 'SENTRY_ACCESS_TOKEN')) {
    $val = [Environment]::GetEnvironmentVariable($envName)
    if ($val) { $agentBlock += "`n`$env:$envName = '$val'" }
}
# Write into both profiles: Windows PowerShell 5.1 and PowerShell 7.
$profilePaths = @(
    (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
)
foreach ($pp in $profilePaths) {
    Set-ManagedBlock -File $pp -Begin '# >>> launchpad (agents) >>>' -End '# <<< launchpad (agents) <<<' -Content $agentBlock
}
# Make the token available right now too, so Codex's config is testable.
if (Have gh) { $env:GITHUB_PAT_TOKEN = (gh auth token 2>$null) }

# --- 5. MCP servers for Claude Code (CLI, idempotent) -------------------------
Log-Info 'Registering MCP servers for Claude Code...'
$devDirFwd = $script:DEVELOPER_DIR -replace '\\', '/'
if ($env:CONTEXT7_API_KEY) {
    Claude-McpAddStdio 'context7' @('cmd', '/c', 'npx', '-y', '@upstash/context7-mcp', '--api-key', $env:CONTEXT7_API_KEY)
} else {
    Claude-McpAddStdio 'context7' @('cmd', '/c', 'npx', '-y', '@upstash/context7-mcp')
}
Claude-McpAddStdio 'playwright' @('cmd', '/c', 'npx', '-y', '@playwright/mcp@latest', '--headless', '--isolated')
Claude-McpAddStdio 'filesystem' @('cmd', '/c', 'npx', '-y', '@modelcontextprotocol/server-filesystem', $devDirFwd)
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Claude-McpAddHttp 'github' 'https://api.githubcopilot.com/mcp/' @('--header', "Authorization: Bearer $(gh auth token 2>$null)")
} else {
    Log-Warn "GitHub not authenticated - skipping GitHub MCP for Claude (run 'gh auth login', then re-run this module)"
}
# Sentry MCP — hosted endpoint with a one-time browser sign-in (/mcp in Claude).
Claude-McpAddHttp 'sentry' 'https://mcp.sentry.dev/mcp'

# --- 6. MCP servers for Codex (managed [mcp_servers.*] block at end of file) --
Log-Info 'Registering MCP servers for Codex...'
$ctx7Args = '["/c", "npx", "-y", "@upstash/context7-mcp"]'
if ($env:CONTEXT7_API_KEY) {
    $ctx7Args = '["/c", "npx", "-y", "@upstash/context7-mcp", "--api-key", "' + $env:CONTEXT7_API_KEY + '"]'
}
$codexBlock = @"
[mcp_servers.context7]
command = "cmd"
args = $ctx7Args

[mcp_servers.playwright]
command = "cmd"
args = ["/c", "npx", "-y", "@playwright/mcp@latest", "--headless", "--isolated"]

[mcp_servers.filesystem]
command = "cmd"
args = ["/c", "npx", "-y", "@modelcontextprotocol/server-filesystem", "$devDirFwd"]

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_PAT_TOKEN"

[mcp_servers.sentry]
url = "https://mcp.sentry.dev/mcp"
"@
Set-ManagedBlock -File $codexCfg -Begin '# >>> launchpad mcp >>>' -End '# <<< launchpad mcp <<<' -Content $codexBlock
Log-Ok 'Codex MCP servers written to ~\.codex\config.toml'

# --- 6b. Antigravity (agy): dark theme + MCP ----------------------------------
Log-Info 'Configuring Antigravity CLI (agy)...'
$agyDir = Join-Path $HOME '.gemini\antigravity-cli'
Ensure-Dir $agyDir

# Dark theme (best-effort; also pre-answers the first-run theme prompt).
$null = Merge-JsonFile -File (Join-Path $agyDir 'settings.json') -Overrides @{ colorScheme = 'dark' }

# MCP servers — the same five, merged (not clobbered) into agy's JSON config.
$ctx7ArgList = @('/c', 'npx', '-y', '@upstash/context7-mcp')
if ($env:CONTEXT7_API_KEY) { $ctx7ArgList += @('--api-key', $env:CONTEXT7_API_KEY) }
$agyServers = @{
    context7   = @{ command = 'cmd'; args = $ctx7ArgList }
    playwright = @{ command = 'cmd'; args = @('/c', 'npx', '-y', '@playwright/mcp@latest', '--headless', '--isolated') }
    filesystem = @{ command = 'cmd'; args = @('/c', 'npx', '-y', '@modelcontextprotocol/server-filesystem', $devDirFwd) }
    sentry     = @{ serverUrl = 'https://mcp.sentry.dev/mcp' }
}
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $agyServers.github = @{ serverUrl = 'https://api.githubcopilot.com/mcp/'; headers = @{ Authorization = "Bearer $(gh auth token 2>$null)" } }
}
if (Merge-JsonFile -File (Join-Path $agyDir 'mcp_config.json') -Overrides @{ mcpServers = $agyServers }) {
    Log-Ok 'agy: MCP servers written to ~\.gemini\antigravity-cli\mcp_config.json'
}
Log-Ok 'Antigravity (agy): autonomy + shared house-rules + dark theme + MCP'

# --- 6d. here.now skill (publish sites + cloud drives) for all three agents ---
Log-Info 'Installing the here.now skill for all three agents...'
function Find-HereNowSkill {
    foreach ($c in @((Join-Path $HOME '.claude\skills\here-now'), (Join-Path $HOME '.agents\skills\here-now'))) {
        if (Test-Path (Join-Path $c 'SKILL.md')) { return $c }
    }
    return $null
}
$hnSrc = Find-HereNowSkill
if (-not $hnSrc) {
    npx -y skills add heredotnow/skill --skill here-now -g >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -ne 0) { Log-Warn "here.now skill install failed (see $env:LAUNCHPAD_LOG)" }
    $hnSrc = Find-HereNowSkill
}
if ($hnSrc) {
    foreach ($dst in @((Join-Path $HOME '.claude\skills\here-now'),
                       (Join-Path $HOME '.agents\skills\here-now'),
                       (Join-Path $agyDir 'skills\here-now'))) {
        if ($dst -eq $hnSrc) { continue }
        Ensure-Dir $dst
        Copy-Item -Recurse -Force (Join-Path $hnSrc '*') $dst
    }
    Log-Ok 'here.now skill ready for Claude, Codex, and Antigravity'
} else {
    Log-Warn "here.now skill not installed - re-run this module once you're online"
}

Log-Ok 'Agents configured: full autonomy, shared house-rules, 5 MCP servers each'

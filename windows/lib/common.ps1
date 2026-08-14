# windows/lib/common.ps1 — shared helpers for Windows Launchpad.
# Dot-source this at the top of every module:
#   . "$PSScriptRoot\..\lib\common.ps1"
#
# The PowerShell twin of lib/common.sh: logging (mirrored to a logfile),
# idempotency guards, file backup, managed marker blocks, winget helpers, and
# idempotent MCP registration for Claude Code.
#
# Design notes (same contract as the bash side):
#   * Dot-sourcing more than once is safe (guarded below).
#   * Helpers log failures and keep going — one failed install never kills an
#     unattended run; doctor.ps1 catches it.
#   * Everything here must run on Windows PowerShell 5.1 as well as pwsh 7.

if ($script:LP_COMMON_SOURCED) { return }
$script:LP_COMMON_SOURCED = $true

# --- paths -------------------------------------------------------------------
$script:LP_LIB_DIR = $PSScriptRoot
$script:LP_ROOT    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$env:LAUNCHPAD_LOG = if ($env:LAUNCHPAD_LOG) { $env:LAUNCHPAD_LOG } else { Join-Path $HOME 'launchpad-setup.log' }
$script:DEVELOPER_DIR = if ($env:DEVELOPER_DIR) { $env:DEVELOPER_DIR } else { Join-Path $HOME 'Developer' }
if (-not $env:LAUNCHPAD_NONINTERACTIVE) { $env:LAUNCHPAD_NONINTERACTIVE = '0' }

# --- logging -----------------------------------------------------------------
function Lp-FileLog([string]$Line) {
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $env:LAUNCHPAD_LOG -Value "$ts $Line" -ErrorAction SilentlyContinue
    } catch { }
}
function Log-Info([string]$Msg) { Lp-FileLog "[ .. ] $Msg"; Write-Host "   $Msg" }
function Log-Ok  ([string]$Msg) { Lp-FileLog "[ OK ] $Msg"; Write-Host "   " -NoNewline; Write-Host ([char]0x2714) -ForegroundColor Green -NoNewline; Write-Host " $Msg" }
function Log-Warn([string]$Msg) { Lp-FileLog "[ !! ] $Msg"; Write-Host "   " -NoNewline; Write-Host '!' -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }
function Log-Err ([string]$Msg) { Lp-FileLog "[ XX ] $Msg"; Write-Host "   " -NoNewline; Write-Host ([char]0x2718) -ForegroundColor Red -NoNewline; Write-Host " $Msg" }
function Log-Note([string]$Msg) { Lp-FileLog "[note] $Msg"; Write-Host "   $Msg" -ForegroundColor DarkGray }
function Log-Step([string]$Msg) {
    Lp-FileLog "==> $Msg"
    Write-Host ''
    Write-Host '==>' -ForegroundColor Blue -NoNewline
    Write-Host " $Msg"
}
function Lp-Die([string]$Msg) { Log-Err $Msg; exit 1 }

# --- small utilities ---------------------------------------------------------
function Have([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

# Back up a file to <file>.backup.<timestamp> before we touch it.
function Backup-File([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$Path.backup.$stamp"
    try { Copy-Item -Path $Path -Destination $backup -Force; Log-Note "backed up $Path -> $backup" } catch { }
}

# Write a text file as UTF-8 WITHOUT a BOM. Windows PowerShell 5.1's
# `Set-Content -Encoding UTF8` writes a BOM, and strict parsers (Codex's TOML
# reader, git's excludesfile) choke on a leading U+FEFF — so every config write
# in the Windows path goes through here.
function Write-LpFile([string]$Path, [string]$Content) {
    Ensure-Dir (Split-Path $Path -Parent)
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

# The real PowerShell profile locations. Documents is often redirected by
# OneDrive Known Folder Move (the default on consumer Windows 11), so derive it
# from the shell folder API — never hardcode $HOME\Documents.
function Get-LpProfilePaths {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $HOME 'Documents' }
    return @(
        (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')
    )
}

function Is-Interactive {
    return ($env:LAUNCHPAD_NONINTERACTIVE -ne '1' -and [Environment]::UserInteractive)
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Re-read Machine + User PATH so tools winget just installed are found in this
# session (the process PATH is a snapshot from before the install).
function Refresh-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
    # User-local bin dirs the native installers use (claude, uv tools, agy).
    foreach ($p in @((Join-Path $HOME '.local\bin'), (Join-Path $env:LOCALAPPDATA 'agy\bin'))) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
    }
}

# Replace (or create) a marker-delimited managed block in a text file.
# Re-running replaces the block in place — never duplicates.
#   Set-ManagedBlock -File $PROFILE -Begin '# >>> x >>>' -End '# <<< x <<<' -Content $text
function Set-ManagedBlock([string]$File, [string]$Begin, [string]$End, [string]$Content) {
    Ensure-Dir (Split-Path $File -Parent)
    $kept = @()
    if (Test-Path $File) {
        Backup-File $File
        $skip = $false
        foreach ($line in (Get-Content $File)) {
            if ($line -eq $Begin) { $skip = $true; continue }
            if ($line -eq $End)   { $skip = $false; continue }
            if (-not $skip) { $kept += $line }
        }
        # Drop trailing blank lines so repeated runs are byte-stable.
        while ($kept.Count -gt 0 -and $kept[$kept.Count - 1] -match '^\s*$') {
            if ($kept.Count -eq 1) { $kept = @() }
            else { $kept = @($kept[0..($kept.Count - 2)]) }
        }
        if ($kept.Count -gt 0) { $kept += '' }
    }
    $block = @($Begin) + ($Content -split "`r?`n") + @($End)
    Write-LpFile $File ((($kept + $block) -join [Environment]::NewLine) + [Environment]::NewLine)
    Log-Note "updated managed block in $File"
}

# Deep-merge a hashtable of overrides into a JSON file (create if missing,
# back up + merge if valid, warn + leave alone if unparseable). The PowerShell
# twin of the repo's `jq -s '.[0] * .[1]'` pattern.
function Merge-JsonFile([string]$File, [hashtable]$Overrides) {
    Ensure-Dir (Split-Path $File -Parent)
    $existing = $null
    if (Test-Path $File) {
        try { $existing = Get-Content $File -Raw | ConvertFrom-Json } catch {
            Log-Warn "could not parse $File — leaving it untouched"
            return $false
        }
        Backup-File $File
    }
    if ($null -eq $existing) { $existing = New-Object PSObject }
    function Merge-Into($Target, [hashtable]$Src) {
        foreach ($key in $Src.Keys) {
            $val = $Src[$key]
            $existingProp = $Target.PSObject.Properties[$key]
            if ($val -is [hashtable] -and $existingProp -and $existingProp.Value -is [PSObject] -and $existingProp.Value -isnot [string]) {
                Merge-Into $existingProp.Value $val
            } else {
                if ($val -is [hashtable]) {
                    $obj = New-Object PSObject
                    Merge-Into $obj $val
                    $val = $obj
                }
                if ($existingProp) { $existingProp.Value = $val }
                else { $Target | Add-Member -NotePropertyName $key -NotePropertyValue $val }
            }
        }
    }
    Merge-Into $existing $Overrides
    Write-LpFile $File (($existing | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
    return $true
}

# Convert a ConvertFrom-Json PSObject tree into nested hashtables, so a JSON
# file from the repo can be fed straight into Merge-JsonFile.
function ConvertTo-LpHashtable($Obj) {
    if ($Obj -is [PSObject] -and $Obj -isnot [string] -and $Obj -isnot [ValueType] -and $Obj -isnot [array]) {
        $h = @{}
        foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-LpHashtable $p.Value }
        return $h
    }
    return $Obj
}

# --- winget ------------------------------------------------------------------
function Winget-Installed([string]$Id) {
    if (-not (Have winget)) { return $false }
    winget list --id $Id -e --accept-source-agreements 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Install one or more winget packages idempotently (silent, unattended).
function Winget-Install([string[]]$Ids) {
    if (-not (Have winget)) { Log-Warn "winget not available — skipped: $($Ids -join ', ')"; return }
    foreach ($id in $Ids) {
        if (Winget-Installed $id) { Log-Ok "package present: $id"; continue }
        Log-Info "installing: $id"
        winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Log-Ok "installed: $id" }
        else { Log-Warn "failed to install $id (see $env:LAUNCHPAD_LOG)" }
    }
    Refresh-SessionPath
}

# --- Git Bash (ships with Git for Windows) -----------------------------------
# The platform-neutral project scripts (harden-project.sh, new-project.sh,
# template scaffolds) run unchanged through this.
function Get-GitBash {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    $bash = Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) 'bin\bash.exe'
    if (Test-Path $bash) { return $bash }
    return $null
}

# --- MCP registration (idempotent, same CLI as macOS) ------------------------
function Claude-McpHas([string]$Name) {
    if (-not (Have claude)) { return $false }
    claude mcp get $Name >$null 2>&1
    return ($LASTEXITCODE -eq 0)
}

# Claude-McpAddStdio context7 @('cmd','/c','npx','-y','@upstash/context7-mcp')
# npx is npx.cmd on Windows, so stdio servers get the `cmd /c` wrapper.
function Claude-McpAddStdio([string]$Name, [string[]]$CommandLine) {
    if (-not (Have claude)) { Log-Warn "claude not on PATH; skipping MCP '$Name'"; return }
    if (Claude-McpHas $Name) { Log-Ok "claude MCP '$Name' already set"; return }
    claude mcp add --scope user $Name -- @CommandLine >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) { Log-Ok "claude MCP '$Name' added" }
    else { Log-Warn "claude MCP '$Name' add failed" }
}

function Claude-McpAddHttp([string]$Name, [string]$Url, [string[]]$ExtraArgs = @()) {
    if (-not (Have claude)) { Log-Warn "claude not on PATH; skipping MCP '$Name'"; return }
    if (Claude-McpHas $Name) { Log-Ok "claude MCP '$Name' already set"; return }
    claude mcp add --scope user --transport http $Name $Url @ExtraArgs >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) { Log-Ok "claude MCP '$Name' added (http)" }
    else { Log-Warn "claude MCP '$Name' add failed" }
}

if (-not $env:LP_QUIET) { Log-Note "common.ps1 loaded (root=$script:LP_ROOT)" }

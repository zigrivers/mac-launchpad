$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:LP_QUIET = '1'
. (Join-Path $root 'windows\lib\common.ps1')

$legacyShellCalls = Get-ChildItem -LiteralPath (Join-Path $root 'windows'), (Join-Path $root 'config\windows') -Recurse -File -Filter '*.ps1' |
    Select-String -SimpleMatch '--shell power-shell'
if ($legacyShellCalls) {
    throw "Found legacy fnm shell spelling at $($legacyShellCalls[0].Path):$($legacyShellCalls[0].LineNumber)."
}

if (-not (Have fnm)) {
    Write-Host 'SKIP: fnm is not installed.'
    exit 0
}

$commands = @('node', 'npm', 'pnpm', 'agent-browser')
foreach ($command in $commands) {
    if (-not (Have $command)) {
        Write-Host "SKIP: $command is not installed before the PATH refresh."
        exit 0
    }
}

$nodeVersion = node --version

# Refresh-SessionPath must restore Launchpad's default fnm Node environment.
# Otherwise npm-installed commands disappear during setup and doctor runs.
Refresh-SessionPath

if ($env:Path -notmatch 'fnm_multishells') {
    throw 'Refresh-SessionPath did not activate fnm in the refreshed PATH.'
}
foreach ($command in $commands) {
    if (-not (Have $command)) {
        throw "Refresh-SessionPath left $command unavailable."
    }
}
if ((node --version) -ne $nodeVersion) {
    throw 'Refresh-SessionPath changed the active Node version.'
}

Write-Host 'PASS: Refresh-SessionPath restores Node and its global tools.'

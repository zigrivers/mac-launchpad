param(
    [switch]$RequireTools,
    [switch]$RequireNonDefault
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:LP_QUIET = '1'
. (Join-Path $root 'windows\lib\common.ps1')

$legacyShellCalls = Get-ChildItem -LiteralPath (Join-Path $root 'windows'), (Join-Path $root 'config\windows') -Recurse -File -Filter '*.ps1' |
    Select-String -SimpleMatch '--shell power-shell'
if ($legacyShellCalls) {
    throw "Found legacy fnm shell spelling at $($legacyShellCalls[0].Path):$($legacyShellCalls[0].LineNumber)."
}
$invalidSilentCall = Select-String -LiteralPath (Join-Path $root 'windows\lib\common.ps1') -SimpleMatch 'fnm use --silent '
if ($invalidSilentCall) {
    throw "Found unsupported fnm --silent option at $($invalidSilentCall.Path):$($invalidSilentCall.LineNumber)."
}

if (-not (Have fnm)) {
    if ($RequireTools) { throw 'fnm is required for this test.' }
    Write-Host 'SKIP: fnm is not installed.'
    exit 0
}

$commands = @('node', 'npm', 'pnpm', 'agent-browser')
foreach ($command in $commands) {
    if (-not (Have $command)) {
        if ($RequireTools) { throw "$command is required for this test." }
        Write-Host "SKIP: $command is not installed before the PATH refresh."
        exit 0
    }
}

$nodeVersion = node --version
$defaultNodeVersion = fnm default 2>$null
if ($RequireNonDefault -and $nodeVersion -eq $defaultNodeVersion) {
    throw 'This test requires an active Node version that differs from the fnm default.'
}

# Refresh-SessionPath must restore Launchpad's active fnm Node environment.
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

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:LP_QUIET = '1'
. (Join-Path $root 'windows\lib\common.ps1')

# Refresh-SessionPath must preserve/restore fnm's active Node environment.
# Otherwise npm-installed commands such as pnpm and agent-browser disappear
# during install and doctor runs even though they are installed.
Refresh-SessionPath

if (Have fnm) {
    if ($env:Path -notmatch 'fnm_multishells') {
        throw 'Refresh-SessionPath did not activate fnm in the refreshed PATH.'
    }
    if (-not (Have node)) {
        throw 'Refresh-SessionPath left Node unavailable after activating fnm.'
    }
}

Write-Host 'PASS: Refresh-SessionPath preserves the fnm Node environment.'

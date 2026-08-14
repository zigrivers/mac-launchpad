# 01-shell — wire up the PowerShell profiles (fnm, Starship, helpers, mkproj)
# and install the Starship prompt config. Windows twin of modules/01-shell.sh
# (a managed profile block instead of ~/.zshrc).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Log-Step '01 · Shell'

# --- PowerShell profile managed block -----------------------------------------
# Write into both profiles: Windows PowerShell 5.1 and PowerShell 7.
$profileContent = Get-Content (Join-Path $script:LP_ROOT 'config\windows\profile.append.ps1') -Raw
$profilePaths = @(
    (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
)
foreach ($pp in $profilePaths) {
    Set-ManagedBlock -File $pp -Begin '# >>> launchpad (profile) >>>' -End '# <<< launchpad (profile) <<<' -Content $profileContent
}
Log-Ok 'configured PowerShell profiles (managed block)'

# --- Starship prompt config ---------------------------------------------------
Ensure-Dir (Join-Path $HOME '.config')
$starshipCfg = Join-Path $HOME '.config\starship.toml'
if (Test-Path $starshipCfg) { Backup-File $starshipCfg }
Copy-Item -Force (Join-Path $script:LP_ROOT 'config\starship.toml') $starshipCfg
Log-Ok 'installed ~\.config\starship.toml'

# --- macOS quality-of-life defaults: SKIPPED ----------------------------------
# The bash original's `defaults write` keyboard/Finder tweaks are macOS-only.

Log-Ok 'Shell complete'

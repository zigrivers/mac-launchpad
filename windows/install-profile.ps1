# windows/install-profile.ps1 <profile>
#
# The Windows twin of scripts/install-profile.sh: maps a profile
# (profiles/<name>.yaml — shared with macOS) to Windows module scripts and runs
# them in numeric order, then runs doctor. The core modules always run;
# 10/12/15/20/30/40 run per the profile's area list.
#
# Invoke as:
#   powershell -NoProfile -ExecutionPolicy Bypass -File windows\install-profile.ps1 everything
#
# Set LAUNCHPAD_NONINTERACTIVE=1 to skip steps that need a human (gh login).

param([string]$ProfileName = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

if (-not $ProfileName) {
    Lp-Die 'usage: install-profile.ps1 <web-starter|full-stack|indie-game|ml-lab|everything>'
}
$profileFile = Join-Path $script:LP_ROOT "profiles\$ProfileName.yaml"
if (-not (Test-Path $profileFile)) {
    Lp-Die "Unknown profile '$ProfileName' (no such file: $profileFile)"
}

Log-Step "Launchpad (Windows) - installing profile: $ProfileName"

$modulesDir = Join-Path $script:LP_ROOT 'windows\modules'
function Run-Module([string]$Name) {
    $path = Join-Path $modulesDir $Name
    if (-not (Test-Path $path)) { Log-Warn "missing module: $Name"; return }
    Log-Step "Module: $Name"
    try {
        & $path
        Log-Ok "module $Name complete"
    } catch {
        Log-Warn "module $Name reported errors: $($_.Exception.Message) (continuing - doctor will catch it)"
    }
}

# --- core modules: every profile (no 07-secrets on Windows yet: the 1Password
#     wiring is a later add-on; .env.local files work without it) ---
$core = @('00-foundation.ps1', '01-shell.ps1', '02-terminal.ps1', '03-editors.ps1',
          '05-agents.ps1', '06-skills.ps1', '08-safety.ps1', '09-dx.ps1')
foreach ($m in $core) { Run-Module $m }

# --- profile-selected area modules (same yaml parsing as the bash runner) ---
$areas = @()
foreach ($line in (Get-Content $profileFile)) {
    if ($line -match '^\s*-\s+([A-Za-z]+)') { $areas += $Matches[1].ToLower() }
}
$env:LAUNCHPAD_AREAS = ' ' + ($areas -join ' ')

$selected = @()
foreach ($area in $areas) {
    switch ($area) {
        'web'    { $selected += @('10-web.ps1', '12-containers.ps1', '15-testing.ps1') }
        'mobile' { $selected += @('20-mobile.ps1') }
        'games'  { $selected += @('30-games.ps1') }
        'ml'     { $selected += @('40-ml.ps1', '12-containers.ps1') }
        default  { Log-Warn "unknown area '$area' in $profileFile" }
    }
}
foreach ($m in ($selected | Sort-Object -Unique)) { Run-Module $m }

# --- health check ---
Log-Step 'Verifying the install (doctor)'
& (Join-Path $script:LP_ROOT 'windows\lib\doctor.ps1') $ProfileName
if ($LASTEXITCODE -eq 0) {
    Log-Ok "doctor: all green for profile '$ProfileName'"
} else {
    Log-Warn 'doctor found issues - review the red lines above and re-run.'
}
exit $LASTEXITCODE

# 02-terminal — Windows Terminal + the Catppuccin Mocha theme. Windows twin of
# modules/02-terminal.sh (Windows Terminal replaces Alacritty on Windows;
# preinstalled on Windows 11, and the install is idempotent anyway).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Log-Step '02 · Terminal (Windows Terminal)'

Winget-Install @('Microsoft.WindowsTerminal', 'Microsoft.PowerShell')

# Alacritty + its Catppuccin theme download: SKIPPED — Windows Terminal is the
# native terminal here; the same Catppuccin Mocha palette is applied below from
# the vendored config\windows\terminal-settings.json (no network needed).

# --- merge the Catppuccin Mocha scheme + profile defaults ---------------------
$fragment = Get-Content (Join-Path $script:LP_ROOT 'config\windows\terminal-settings.json') -Raw | ConvertFrom-Json
$wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (-not (Test-Path $wtSettings)) {
    # Terminal writes its settings file on first launch — don't create it for it.
    Log-Note 'Windows Terminal has no settings.json yet - launch it once, then re-run this module to apply the theme'
} else {
    try {
        $settings = Get-Content $wtSettings -Raw | ConvertFrom-Json
        Backup-File $wtSettings
        # Append the scheme unless one with the same name is already there.
        $schemeName = $fragment.scheme.name
        $schemes = @()
        if ($settings.PSObject.Properties['schemes']) { $schemes = @($settings.schemes) }
        $already = $false
        foreach ($s in $schemes) { if ($s.name -eq $schemeName) { $already = $true } }
        if (-not $already) {
            $schemes += $fragment.scheme
            if ($settings.PSObject.Properties['schemes']) { $settings.schemes = $schemes }
            else { $settings | Add-Member -NotePropertyName schemes -NotePropertyValue $schemes }
        }
        # Set profiles.defaults.colorScheme + font from the fragment.
        if (-not $settings.PSObject.Properties['profiles']) {
            $settings | Add-Member -NotePropertyName profiles -NotePropertyValue (New-Object PSObject)
        }
        if ($settings.profiles -is [array]) {
            # Legacy array-form "profiles" (old carried-over settings.json) has
            # no defaults object — write the scheme only and say so honestly.
            Log-Warn 'Windows Terminal settings use the legacy list format - added the Catppuccin Mocha scheme, but pick it (and the JetBrainsMono Nerd Font) in Terminal Settings yourself'
        } else {
            if (-not $settings.profiles.PSObject.Properties['defaults']) {
                $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue (New-Object PSObject)
            }
            $defaults = $settings.profiles.defaults
            if ($defaults.PSObject.Properties['colorScheme']) { $defaults.colorScheme = $fragment.profileDefaults.colorScheme }
            else { $defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue $fragment.profileDefaults.colorScheme }
            if ($defaults.PSObject.Properties['font']) { $defaults.font = $fragment.profileDefaults.font }
            else { $defaults | Add-Member -NotePropertyName font -NotePropertyValue $fragment.profileDefaults.font }
        }
        Write-LpFile $wtSettings (($settings | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
        if ($settings.profiles -isnot [array]) {
            Log-Ok 'applied Catppuccin Mocha theme + font to Windows Terminal'
        }
    } catch {
        Log-Warn "could not parse Windows Terminal settings.json - left as-is (set the theme in its UI): $($_.Exception.Message)"
    }
}

Log-Ok 'Terminal complete'

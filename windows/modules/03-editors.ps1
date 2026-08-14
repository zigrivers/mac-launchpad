# 03-editors — VS Code with the Claude Code and Codex extensions, Catppuccin
# Mocha, and JetBrainsMono Nerd Font. Windows twin of modules/03-editors.sh.
#
# Verified extension IDs (2026-06): Claude Code = anthropic.claude-code,
# Codex = openai.chatgpt (NOT openai.codex) — same IDs as macOS.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Log-Step '03 · Editors'

Winget-Install @('Microsoft.VisualStudioCode')
Refresh-SessionPath

# Cursor + Sublime Text: SKIPPED — deferred on Windows v1 (VS Code covers the
# editor role; add them back once their Windows setup is verified).

# --- install extensions into VS Code ------------------------------------------
if (Have code) {
    Log-Ok "CLI 'code' on PATH"
    foreach ($ext in @('Catppuccin.catppuccin-vsc', 'anthropic.claude-code', 'openai.chatgpt')) {
        code --install-extension $ext --force >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) { Log-Ok "code: $ext" }
        else { Log-Warn "code: could not install $ext (see $env:LAUNCHPAD_LOG)" }
    }
} else {
    Log-Warn "CLI 'code' not found on PATH yet - open a new window and re-run this module for extensions"
}

# --- deep-merge our theme/font settings without clobbering the user's ---------
$codeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
if (Merge-JsonFile -File $codeSettings -Overrides @{
    'workbench.colorTheme'              = 'Catppuccin Mocha'
    'editor.fontFamily'                 = 'JetBrainsMono Nerd Font, Consolas, monospace'
    'editor.fontLigatures'              = $true
    'editor.fontSize'                   = 14
    'terminal.integrated.fontFamily'    = 'JetBrainsMono Nerd Font'
}) {
    Log-Ok 'VS Code: merged settings.json'
}

Log-Ok 'Editors complete'

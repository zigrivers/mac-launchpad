# launchpad (Windows) — one friendly command for the whole setup. A .cmd shim
# on PATH (written by 09-dx.ps1) runs this file, so `launchpad` works in
# PowerShell, CMD, and Git Bash alike.
#
# The project-safety commands (new / harden) reuse the SAME bash scripts as
# macOS, run through Git Bash — one source of truth for that logic. The rest is
# implemented natively or marked "not on Windows yet".

param(
    [string]$Command = 'help',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

$ErrorActionPreference = 'Continue'
$env:LP_QUIET = '1'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

function Invoke-RepoBash([string]$Script, [string[]]$BashArgs) {
    $bash = Get-GitBash
    if (-not $bash) {
        Log-Err 'Git Bash not found (it comes with Git for Windows). Run the setup again, or install Git first.'
        exit 1
    }
    # Git Bash understands C:/-style paths; convert backslashes only.
    $scriptPath = (Join-Path $script:LP_ROOT $Script) -replace '\\', '/'
    $converted = @()
    foreach ($a in $BashArgs) { $converted += ($a -replace '\\', '/') }
    & $bash $scriptPath @converted
    exit $LASTEXITCODE
}

function Show-Toast([string]$Message) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $texts = $xml.GetElementsByTagName('text')
        $texts.Item(0).AppendChild($xml.CreateTextNode('Launchpad')) | Out-Null
        $texts.Item(1).AppendChild($xml.CreateTextNode($Message)) | Out-Null
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Launchpad').Show($toast)
    } catch {
        Write-Host "[notify] $Message"
    }
}

function Show-Usage {
    Write-Host @'
launchpad — your setup's command center (Windows)

  launchpad new       Start a new project from a template (safe + backed up)
  launchpad harden    Secure an existing folder (secret-scan hook + private backup)
  launchpad doctor    Health-check your setup (green / red)
  launchpad update    Update all your tools
  launchpad notify    Send yourself a desktop notification
  launchpad help      Show this message

Not on Windows yet (coming in a later update — ask an assistant for the
equivalent): report, spend, nudge, secrets, status, signin, sentry-setup, add.

Tip: you can also just ask an assistant in plain English — "start a new
project", "run the doctor check" — and it will run the right one for you.
'@
}

switch ($Command) {
    'new'    { Invoke-RepoBash 'scripts/new-project.sh' $Rest }
    'harden' { Invoke-RepoBash 'scripts/harden-project.sh' $Rest }
    'doctor' {
        & (Join-Path $script:LP_ROOT 'windows\lib\doctor.ps1') @Rest
        exit $LASTEXITCODE
    }
    'update' {
        Log-Step 'Updating your tools'
        if (Have winget) {
            winget upgrade --all --silent --accept-package-agreements --accept-source-agreements
        }
        if (Have npm) {
            Log-Info 'updating global npm tools...'
            npm update -g >> $env:LAUNCHPAD_LOG 2>&1
        }
        if (Have uv) {
            uv tool upgrade --all >> $env:LAUNCHPAD_LOG 2>&1
        }
        Log-Ok 'update pass complete (claude, codex, and agy keep themselves current)'
    }
    'notify' {
        $msg = if ($Rest.Count -gt 0) { $Rest -join ' ' } else { 'Done.' }
        Show-Toast $msg
    }
    'help'   { Show-Usage }
    { $_ -in @('report', 'spend', 'nudge', 'secrets', 'status', 'signin', 'sentry-setup', 'add') } {
        Write-Host "launchpad $Command isn't available on Windows yet - it's coming in a later update."
        Write-Host 'Ask an assistant in plain English instead (e.g. "check my AI spend", "set up error tracking").'
    }
    default  { Show-Usage }
}

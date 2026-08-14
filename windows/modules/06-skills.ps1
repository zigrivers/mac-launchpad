# 06-skills — the Superpowers engineering-workflow framework + a curated,
# cross-agent skill set. Runs for every profile, after 05-agents.
# Windows twin of modules/06-skills.sh.
#
# Two install mechanisms (same as the bash side):
#   * Superpowers is a full framework (hooks + meta-skill), installed natively.
#       - Claude Code: `claude plugin install` (a real, scriptable CLI — slash
#         commands like /plugin are user-only and can't be scripted).
#       - Codex + Antigravity: no scriptable native path, so DEGRADED MODE —
#         install Superpowers' skill *content* via the cross-agent skills CLI
#         and let the shared AGENTS.md carry the workflow instructions.
#   * Everything else: the Vercel `skills` CLI (`npx skills`), which targets
#     claude-code, codex, and antigravity-cli in one command.
#
# Name/target corrections baked in: agy = `antigravity-cli` (not `antigravity`);
# frontend-design/skill-creator live in anthropics/skills (not vercel-labs).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Refresh-SessionPath

Log-Step '06 · Agent Skills (Superpowers + curated set)'

# Need Node/npx for the skills CLI.
if (Have fnm) { fnm env --shell power-shell 2>$null | Out-String | Invoke-Expression }
$npxOk = Have npx
if (-not $npxOk) {
    Log-Warn 'npx not available yet — skills CLI needs Node. Re-run after 00-foundation.'
}

# --- Superpowers: Claude Code (native plugin via the scriptable CLI) ---------
if (Have claude) {
    $plugins = claude plugin list 2>$null | Out-String
    if ($plugins -match 'superpowers') {
        Log-Ok 'Superpowers already installed for Claude Code'
    } else {
        claude plugin install superpowers@claude-plugins-official --scope user >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -eq 0) {
            Log-Ok "Superpowers installed for Claude Code (restart 'claude' to activate)"
        } else {
            Log-Warn 'Superpowers install for Claude Code failed — run: claude plugin install superpowers@claude-plugins-official'
        }
    }
} else {
    Log-Warn 'claude not on PATH; skipping Superpowers for Claude Code'
}
# Belt-and-suspenders: declare it enabled in settings.json so it activates on the
# next launch even if the CLI install above couldn't reach the marketplace.
if (Merge-JsonFile -File (Join-Path $HOME '.claude\settings.json') -Overrides @{ enabledPlugins = @{ 'superpowers@claude-plugins-official' = $true } }) {
    Log-Ok 'Superpowers enabled in ~\.claude\settings.json'
}

# --- Superpowers: Codex + Antigravity (degraded mode — skill content) --------
# Native Codex Superpowers is its interactive /plugins UI (not scriptable);
# Antigravity has no native path. Install the skills; AGENTS.md carries workflow.
if ($npxOk) {
    npx -y skills add obra/superpowers -g -y -a codex -a antigravity-cli >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log-Ok 'Superpowers skills installed for Codex + Antigravity (degraded mode)'
    } else {
        Log-Warn "Superpowers degraded-mode install failed (see $env:LAUNCHPAD_LOG)"
    }
}

# --- Curated cross-agent skills (all three agents) ---------------------------
function Add-Skill([string]$Label, [string[]]$SkillArgs) {
    # Add-Skill <label> <repo + --skill flags>
    if (-not $npxOk) { Log-Warn "npx missing; skipping $Label"; return }
    npx -y skills add @SkillArgs -g -y -a claude-code -a codex -a antigravity-cli >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) { Log-Ok "skill: $Label" }
    else { Log-Warn "skill failed: $Label (see $env:LAUNCHPAD_LOG)" }
}
Add-Skill 'agent-browser'         @('vercel-labs/agent-browser')
Add-Skill 'web-design-guidelines' @('vercel-labs/agent-skills', '--skill', 'web-design-guidelines')
Add-Skill 'design + document skills (frontend-design, skill-creator, pdf, docx, pptx, xlsx)' `
    @('anthropics/skills', '--skill', 'frontend-design', '--skill', 'skill-creator', '--skill', 'pdf', '--skill', 'docx', '--skill', 'pptx', '--skill', 'xlsx')

# --- skills-lock.json for reproducibility (experimental upstream feature) -----
# `npx skills` writes it to the current directory; copy into the repo if we can.
if (Test-Path 'skills-lock.json') {
    try {
        Copy-Item -Force 'skills-lock.json' (Join-Path $script:LP_ROOT 'skills-lock.json')
        Log-Ok 'captured skills-lock.json (restore with: npx skills experimental_install)'
    } catch { }
}

Log-Note 'Skills install design/testing/doc abilities + the Superpowers workflow.'
Log-Note "Restart 'claude' once so Superpowers activates for Claude Code."
Log-Ok 'Skills complete'

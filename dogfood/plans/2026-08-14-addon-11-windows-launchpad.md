# Add-on 11 — Windows Launchpad (plan)

**Goal.** Ship Windows support: `bootstrap.ps1` + `windows/` (lib, modules,
install-profile, doctor, launchpad CLI) + a Windows docs journey + platform
routing in `CLAUDE.md`, leaving the Mac path untouched.

**Spec:** `dogfood/specs/2026-08-14-addon-11-windows-launchpad-design.md`
(includes the build-time verified facts, checked 2026-08-14).

## Conventions for the implementer

- Every `windows/modules/*.ps1` dot-sources `windows/lib/common.ps1`, is
  idempotent, warns instead of dying (doctor catches misses), and logs to
  `$HOME\launchpad-setup.log` — mirroring the bash originals section by section.
- `bootstrap.ps1` must run on stock **Windows PowerShell 5.1** (no `&&`, no
  ternary, no pwsh-7-only syntax) because that's what `irm | iex` lands in.
  Stage-1 scripts may assume more, but stay 5.1-safe anyway.
- Any on-disk script is invoked `powershell -NoProfile -ExecutionPolicy Bypass -File …`.
- JSON merges use PowerShell's native `ConvertFrom-Json`/`ConvertTo-Json`
  (no jq dependency for Windows-side config edits).
- One runnable check per non-trivial piece: `tests/test-windows-syntax.sh`
  parses every `.ps1` with the PowerShell parser (skips politely if `pwsh`
  is absent on the machine running the tests).

## Tasks

1. **Core plumbing (by hand):** `windows/lib/common.ps1` (logging, backup,
   managed blocks, winget helpers, PATH refresh), `bootstrap.ps1`,
   `windows/install-profile.ps1` (same profile-yaml parsing), `windows/lib/doctor.ps1`,
   `windows/modules/00-foundation.ps1`, `windows/modules/05-agents.ps1`,
   `windows/scripts/launchpad.ps1`, `config/windows/profile.append.ps1`,
   `config/windows/terminal-settings.json` fragment.
2. **Remaining modules (fan-out, one agent per group, pattern-locked):**
   01-shell / 02-terminal / 03-editors · 06-skills / 08-safety / 09-dx ·
   10-web / 12-containers / 15-testing · 20-mobile / 30-games / 40-ml.
3. **Docs:** `docs/windows.html` (full journey, twin of index), platform
   switcher on `index.html`, Windows note on `getting-started.html`,
   `CLAUDE.md` platform routing, README architecture rows.
4. **Verify:** pwsh parse all `.ps1`; shellcheck touched bash; run `tests/*.sh`;
   screenshot the docs pages with Playwright; `/ponytail-review` + code review
   on the diff.
5. **Ship:** commit, push, PR, merge, prune branches, `launchpad notify`.

Done means: repo merged to main with all checks above green locally, and the
PR body lists exactly what still needs a real Windows PC to confirm.

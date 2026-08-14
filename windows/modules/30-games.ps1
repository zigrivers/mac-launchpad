# 30-games — game engines. Windows twin of modules/30-games.sh.
# Godot is the lightweight default; Unity Hub is the heavier option. Web-game
# stacks (Phaser, Three.js, Babylon.js) need no system install — they're
# scaffolded per-project on Node (see first-app guide).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Log-Step '30 · Games'

Winget-Install @('GodotEngine.GodotEngine', 'Unity.UnityHub')

Log-Note 'Godot is ready to open now — no account needed.'
Log-Note "Unity: open 'Unity Hub', sign in with a (free) Unity account, and install an"
Log-Note '       Editor version from there. Web games need nothing extra — Node has it.'

Log-Ok 'Games complete'

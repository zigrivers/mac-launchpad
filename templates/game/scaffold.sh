#!/usr/bin/env bash
#
# templates/game/scaffold.sh <target-dir>
#
# A browser-game starter that RUNS IMMEDIATELY: Phaser 4 + Vite + TypeScript
# (the official phaserjs/template-vite-ts, MIT). `npm run dev` serves a playable
# game at http://localhost:8080 with hot-reload — perfect for an assistant to
# open and iterate on. No accounts or keys needed.
#
# (Godot is also installed — for that, open the Godot app and create a project
# there; AI agents are much stronger at this web/TypeScript game base.)
#
# Verified 2026-06-15: phaserjs/template-vite-ts (Phaser 4.1, Vite 6, MIT), dev
# server on :8080.

set -uo pipefail
target="${1:?usage: scaffold.sh <target-dir>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO="$(cd "$HERE/../.." >/dev/null 2>&1 && pwd)"

echo "→ Creating a Phaser game (downloading the template)…"
npx --yes degit phaserjs/template-vite-ts "$target" || { echo "degit failed"; exit 1; }

cd "$target" || exit 1

echo "→ Installing dependencies (this takes a minute)…"
npm install >/dev/null 2>&1 || echo "  (npm install had issues — run 'npm install' again in the project)"

cp -f "$REPO/config/dx/biome.json" . 2>/dev/null || true

echo "✓ Phaser game ready (run it with: npm run dev → http://localhost:8080)"

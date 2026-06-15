#!/usr/bin/env bash
#
# templates/mobile/scaffold.sh <target-dir>
#
# A phone-app starter that RUNS IMMEDIATELY on your phone with no accounts or
# keys: Expo (React Native) with Expo Router + TypeScript (a multi-screen layout).
# Scan the QR code with the free "Expo Go" app and it's live on your device.
#
# Verified 2026-06-15: `create-expo-app@latest` default template = Expo Router +
# TypeScript (multi-screen; scaffolds SDK 54 during the SDK-56 transition).
# `npx expo start` runs with zero setup; pass `--template tabs` for a tabbed start.

set -uo pipefail
target="${1:?usage: scaffold.sh <target-dir>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO="$(cd "$HERE/../.." >/dev/null 2>&1 && pwd)"

echo "→ Creating an Expo app (this takes a minute or two)…"
npx --yes create-expo-app@latest "$target" || { echo "create-expo-app failed"; exit 1; }

cd "$target" || exit 1

echo "→ Adding a test setup (jest-expo)…"
npx --yes expo install jest-expo jest @testing-library/react-native >/dev/null 2>&1 || true
if [ -d node_modules/jest-expo ]; then
  npm pkg set scripts.test="jest" >/dev/null 2>&1 || true
  npm pkg set jest.preset="jest-expo" >/dev/null 2>&1 || true
fi

cp -f "$REPO/config/dx/biome.json" . 2>/dev/null || true

echo "✓ Expo app ready (run it on your phone with: npx expo start)"

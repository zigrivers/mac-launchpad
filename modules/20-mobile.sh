#!/usr/bin/env bash
#
# 20-mobile — native iOS + Android toolchains. This is the heaviest module:
# Xcode + Android Studio are a 20+ GB download and take a long while.
# (Expo/React Native needs no global install — use `npx create-expo-app`.)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "20 · Mobile (iOS + Android)"
log_warn "Heads up: this installs Xcode + Android Studio — 20+ GB and slow. Grab a coffee."

# run a sudo command only if we can do so without hanging on a password prompt
maybe_sudo() {
  if sudo -n true 2>/dev/null; then sudo "$@"
  elif is_interactive; then sudo "$@"
  else log_warn "skipping (needs sudo, non-interactive): sudo $*"; return 1; fi
}

# --- React Native / build tooling -------------------------------------------
brew_install watchman cocoapods
brew_cask temurin android-studio

# --- Android SDK location ---------------------------------------------------
# Android Studio installs the SDK to ~/Library/Android/sdk on first launch.
if [ -d "$HOME/Library/Android/sdk" ]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
  log_ok "ANDROID_HOME = $ANDROID_HOME (also exported in ~/.zshrc)"
else
  log_note "Open Android Studio once and complete the setup wizard to install the Android SDK."
  log_note "ANDROID_HOME will then be picked up automatically from ~/.zshrc."
fi

# --- Xcode ------------------------------------------------------------------
if [ -d "/Applications/Xcode.app" ]; then
  log_ok "Xcode already installed"
elif have mas; then
  log_info "Installing Xcode from the App Store (requires being signed into the App Store app)…"
  mas install 497799835 >>"$LAUNCHPAD_LOG" 2>&1 \
    || log_warn "Could not install Xcode via mas. Open the App Store, install Xcode, then re-run this module."
fi

if [ -d "/Applications/Xcode.app" ]; then
  maybe_sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer >>"$LAUNCHPAD_LOG" 2>&1 || true
  if maybe_sudo xcodebuild -license accept >>"$LAUNCHPAD_LOG" 2>&1; then
    log_ok "Accepted the Xcode license"
  else
    log_note "Finish with: sudo xcodebuild -license accept"
  fi
  maybe_sudo xcodebuild -runFirstLaunch >>"$LAUNCHPAD_LOG" 2>&1 || true
fi

log_note "Build a phone app with:  npx create-expo-app@latest my-app"
log_ok "Mobile complete"

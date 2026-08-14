# 20-mobile — the Android toolchain. Windows twin of modules/20-mobile.sh.
# On Windows you build ANDROID apps locally; iOS apps need a Mac or an EAS
# cloud build (docs.expo.dev). Android Studio is still a multi-GB download.
# (Expo/React Native needs no global install — use `npx create-expo-app`.)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Log-Step '20 · Mobile (Android — iOS apps need a Mac or a cloud build)'
Log-Warn 'Heads up: this installs the JDK + Android Studio — a big download and slow. Grab a coffee.'
Log-Note 'iOS builds are macOS-only. Build iOS from a Mac, or use an EAS cloud build (docs.expo.dev).'

# --- React Native / build tooling ---------------------------------------------
# (watchman is not needed on Windows for Expo; cocoapods is iOS/macOS-only.)
Winget-Install @('EclipseAdoptium.Temurin.17.JDK', 'Google.AndroidStudio')

# --- Android SDK location -----------------------------------------------------
# Android Studio installs the SDK to %LOCALAPPDATA%\Android\Sdk on first launch.
if (Test-Path (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) {
    Log-Ok "Android SDK found at $env:LOCALAPPDATA\Android\Sdk"
} else {
    Log-Note 'Open Android Studio once and complete the setup wizard to install the Android SDK.'
    Log-Note "The SDK lands at $env:LOCALAPPDATA\Android\Sdk; the PowerShell profile exports ANDROID_HOME automatically once it exists (config/windows/profile.append.ps1)."
}

# --- Xcode --------------------------------------------------------------------
# Skipped: Xcode, xcode-select, and the license step are macOS-only.

Log-Note 'Build a phone app with:  npx create-expo-app@latest my-app'
Log-Ok 'Mobile complete'

#!/bin/zsh
# Installs the last debug build on the booted iPhone 17 simulator, opens one
# screen with demo data and saves a screenshot to build/screens/.
#   scripts/screenshot.sh <screen> [pl|en] [light|dark] [wait-seconds]
# Screens: see DebugLaunch.Screen (e.g. gym, picker, summary, exerciseDetail).
set -e
cd "${0:A:h}/.."

screen="$1"
lang="${2:-pl}"
appearance="${3:-light}"
wait="${4:-3}"
device="iPhone 17"
app="build/DerivedData/Build/Products/Debug-iphonesimulator/Biegocz.app"
bundle="com.gajtkowski.biegocz"
locale="pl_PL"
[[ "$lang" == "en" ]] && locale="en_GB"

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl ui "$device" appearance "$appearance"
xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
xcrun simctl uninstall "$device" "$bundle" 2>/dev/null || true
xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" "$bundle" -demoData YES -screen "$screen" \
  -AppleLanguages "($lang)" -AppleLocale "$locale" >/dev/null
sleep "$wait"
mkdir -p build/screens
out="build/screens/${screen}-${lang}-${appearance}.png"
xcrun simctl io "$device" screenshot "$out" >/dev/null 2>&1
echo "$out"

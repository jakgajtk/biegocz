#!/bin/zsh
# Takes the App Store screenshots in English and Polish on the 6.9" simulator
# (iPhone 17 Pro Max, 1320 × 2868) with a clean status bar, saved to
# build/store/<lang>/NN-<screen>.png. Needs a debug build (scripts/build.sh).
#   scripts/store_screenshots.sh [light|dark]
set -e
cd "${0:A:h}/.."

appearance="${1:-dark}"
device="iPhone 17 Pro Max"
screens=(start gym history routes activityDetail exerciseDetail)

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi \
  --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100

for lang in en pl; do
  mkdir -p "build/store/$lang"
  i=1
  for screen in $screens; do
    # Routes come from Apple Maps, so give them longer to load.
    wait=4
    [[ "$screen" == "routes" ]] && wait=10
    shot=$(scripts/screenshot.sh "$screen" "$lang" "$appearance" "$wait" "$device")
    mv "$shot" "build/store/$lang/$(printf %02d $i)-$screen.png"
    i=$((i + 1))
  done
done

xcrun simctl status_bar "$device" clear
echo "build/store"

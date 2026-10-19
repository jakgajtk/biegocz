#!/bin/zsh
# Builds (and optionally tests) Biegocz on the iPhone 17 simulator, printing
# only errors, warnings and test results.
#   scripts/build.sh          build app + tests
#   scripts/build.sh test     build and run tests, then print failure messages
set -o pipefail
cd "${0:A:h}/.."

action="build-for-testing"
result_args=()
if [[ "$1" == "test" ]]; then
  action="test"
  rm -rf build/TestResults.xcresult
  result_args=(-resultBundlePath build/TestResults.xcresult)
fi

xcodebuild "$action" \
  -project Biegocz.xcodeproj \
  -scheme Biegocz \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath build/DerivedData \
  "${result_args[@]}" \
  2>&1 | grep -E "error:|warning:|failed|BUILD|TEST " | grep -v "appintentsmetadataprocessor" | sort -u
build_status=${pipestatus[1]}

if [[ "$1" == "test" && -d build/TestResults.xcresult ]]; then
  xcrun xcresulttool get test-results summary --path build/TestResults.xcresult --compact \
    | python3 scripts/test_summary.py
fi
exit $build_status

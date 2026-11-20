#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
source Scripts/swift-sources.sh
mkdir -p build/tests
test_app="build/tests/button-gestures-ui.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
cp -R Resources/*.lproj "$test_app/Contents/Resources/"
print '<plist version="1.0"><dict><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>' > "$test_app/Contents/Info.plist"
xcrun swiftc "${remote_vibe_swift_flags[@]}" \
  "${rv_input_sources[@]}" \
  Tests/mouse_mode_test.swift Tests/mapping_store_test.swift Tests/button_gesture_test.swift -o build/tests/button-gestures
build/tests/button-gestures
xcrun swiftc "${remote_vibe_swift_flags[@]}" \
  "${rv_input_sources[@]}" "${rv_ui_mapping_sources[@]}" \
  Tests/button_gesture_ui_test.swift -o "$test_app/Contents/MacOS/button-gestures-ui"
for language in zh-Hans en; do
  "$test_app/Contents/MacOS/button-gestures-ui" -AppleLanguages "($language)"
done

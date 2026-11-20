#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
source Scripts/swift-sources.sh
mkdir -p build/tests
test_app="build/tests/design-preview.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
cp -R Resources/*.lproj "$test_app/Contents/Resources/"
print '<plist version="1.0"><dict><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>' > "$test_app/Contents/Info.plist"
xcrun swiftc "${remote_vibe_swift_flags[@]}" \
  "${rv_input_sources[@]}" "${rv_ui_mapping_sources[@]}" Sources/UI/ComboUnlockView.swift \
  Tests/design_preview.swift -o "$test_app/Contents/MacOS/design-preview"
"$test_app/Contents/MacOS/design-preview" "${1:-review}" -AppleLanguages "(${2:-zh-Hans})"

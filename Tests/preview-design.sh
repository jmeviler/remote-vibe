#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/tests
test_app="build/tests/design-preview.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
cp -R Resources/*.lproj "$test_app/Contents/Resources/"
print '<plist version="1.0"><dict><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>' > "$test_app/Contents/Info.plist"
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/App/Localization.swift Sources/Bluetooth/RemoteProfile.swift Sources/Bluetooth/ATVVError.swift Sources/Input/FnKey.swift \
  Sources/Input/MousePointer.swift Sources/Input/DesktopActions.swift Sources/Input/ClipboardPaste.swift Sources/Input/ButtonGesture.swift Sources/Input/ActionCatalog.swift Sources/Input/KeyMapping.swift \
  Sources/UI/SettingsUI.swift Sources/UI/KeyMappingView.swift Sources/UI/ComboUnlockView.swift \
  Tests/design_preview.swift -o "$test_app/Contents/MacOS/design-preview"
"$test_app/Contents/MacOS/design-preview" "${1:-review}" -AppleLanguages "(${2:-zh-Hans})"

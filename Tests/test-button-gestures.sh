#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/Bluetooth/RemoteProfile.swift Sources/Bluetooth/ATVVError.swift Sources/Input/FnKey.swift \
  Sources/Input/DesktopActions.swift Sources/Input/ClipboardPaste.swift Sources/Input/ButtonGesture.swift Sources/Input/ActionCatalog.swift Sources/Input/KeyMapping.swift \
  Tests/button_gesture_test.swift -o build/tests/button-gestures
build/tests/button-gestures
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/Bluetooth/RemoteProfile.swift Sources/Bluetooth/ATVVError.swift Sources/Input/FnKey.swift \
  Sources/Input/DesktopActions.swift Sources/Input/ClipboardPaste.swift Sources/Input/ButtonGesture.swift Sources/Input/ActionCatalog.swift Sources/Input/KeyMapping.swift \
  Sources/UI/SettingsUI.swift Sources/UI/KeyMappingView.swift Tests/button_gesture_ui_test.swift -o build/tests/button-gestures-ui
build/tests/button-gestures-ui

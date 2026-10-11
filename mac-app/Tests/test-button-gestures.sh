#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/RemoteProfile.swift Sources/BridgeError.swift Sources/FnKey.swift \
  Sources/DesktopActions.swift Sources/TextInput.swift Sources/ButtonGesture.swift Sources/ActionCatalog.swift Sources/KeyMapping.swift \
  Tests/button_gesture_test.swift -o build/tests/button-gestures
build/tests/button-gestures
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/RemoteProfile.swift Sources/BridgeError.swift Sources/FnKey.swift \
  Sources/DesktopActions.swift Sources/TextInput.swift Sources/ButtonGesture.swift Sources/ActionCatalog.swift Sources/KeyMapping.swift \
  Sources/StudioTheme.swift Sources/KeyMappingView.swift Tests/button_gesture_ui_test.swift -o build/tests/button-gestures-ui
build/tests/button-gestures-ui

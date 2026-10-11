#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/Bluetooth/RemoteProfile.swift Sources/Bluetooth/ATVVError.swift Sources/Input/FnKey.swift \
  Sources/Input/DesktopActions.swift Sources/Input/ClipboardPaste.swift Sources/Input/ButtonGesture.swift Sources/Input/ActionCatalog.swift Sources/Input/KeyMapping.swift \
  Sources/UI/SettingsUI.swift Sources/UI/KeyMappingView.swift Sources/UI/ComboUnlockView.swift \
  Tests/design_preview.swift -o build/tests/design-preview
build/tests/design-preview "${1:-review}"

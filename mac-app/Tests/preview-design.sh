#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/RemoteProfile.swift Sources/BridgeError.swift Sources/FnKey.swift \
  Sources/DesktopActions.swift Sources/TextInput.swift Sources/ButtonGesture.swift Sources/ActionCatalog.swift Sources/KeyMapping.swift \
  Sources/StudioTheme.swift Sources/KeyMappingView.swift Sources/ComboUnlockView.swift \
  Tests/design_preview.swift -o build/tests/design-preview
build/tests/design-preview "${1:-review}"

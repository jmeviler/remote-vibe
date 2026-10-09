#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
build_stage=$(mktemp -d "$PWD/build/stage.XXXXXX")
app="$build_stage/Remote Vibe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 \
  Sources/ATVVProtocol.swift Sources/ADPCMDecoder.swift Sources/BridgeError.swift \
  Sources/Remote.swift Sources/FnKey.swift Sources/VirtualMicrophone.swift \
  Sources/DesktopActions.swift Sources/KeyMapping.swift Sources/KeyMappingView.swift Sources/WeChatApp.swift \
  -o "$app/Contents/MacOS/RemoteVibe"
cp Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp ../LICENSE "$app/Contents/Resources/LICENSE"
codesign --force --sign - --timestamp=none \
  --requirements '=designated => identifier "local.ben.RemoteVibe"' "$app"
codesign --verify --deep --strict "$app"
if [[ -d "build/Remote Vibe.app" ]]; then
  mv "build/Remote Vibe.app" "build/Remote Vibe.previous.$(date +%Y%m%d-%H%M%S).app"
fi
mv "$app" "build/Remote Vibe.app"
rmdir "$build_stage"
print "Built: $PWD/build/Remote Vibe.app"

#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
build_stage=$(mktemp -d "$PWD/build/stage.XXXXXX")
app="$build_stage/Remote Vibe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 \
  Sources/Bluetooth/ATVVProtocol.swift Sources/Audio/ADPCMDecoder.swift Sources/Bluetooth/ATVVError.swift \
  Sources/App/Localization.swift Sources/Bluetooth/RemoteProfile.swift Sources/Audio/RemoteAudioSession.swift Sources/Bluetooth/BluetoothRemote.swift Sources/Bluetooth/RemoteController.swift Sources/Input/XiaomiVoiceKeyOverride.swift \
  Sources/Input/FnKey.swift Sources/Audio/VirtualMicrophone.swift Sources/Audio/VoiceSessionTiming.swift \
  Sources/Input/MousePointer.swift Sources/Input/DesktopActions.swift Sources/Input/ClipboardPaste.swift Sources/Input/ButtonGesture.swift Sources/Input/ActionCatalog.swift Sources/Input/KeyMapping.swift Sources/Input/MappingStore.swift Sources/UI/SettingsUI.swift Sources/UI/KeyMappingView.swift \
  Sources/Unlock/ComboUnlock.swift Sources/UI/ComboUnlockView.swift Sources/App/ReleaseUpdate.swift Sources/App/AppController.swift \
  -o "$app/Contents/MacOS/RemoteVibe"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Docs/THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp LICENSE "$app/Contents/Resources/LICENSE"
(git rev-parse HEAD 2>/dev/null || print source-archive) > "$app/Contents/Resources/Source-Commit.txt"
codesign --force --sign - --timestamp=none \
  --requirements '=designated => identifier "local.ben.RemoteVibe"' "$app"
codesign --verify --deep --strict "$app"
if [[ -d "build/Remote Vibe.app" ]]; then
  mv "build/Remote Vibe.app" "build/Remote Vibe.previous.$(date +%Y%m%d-%H%M%S).app"
fi
mv "$app" "build/Remote Vibe.app"
rmdir "$build_stage"
print "Built: $PWD/build/Remote Vibe.app"

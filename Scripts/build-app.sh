#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source Scripts/build-target.sh
source Scripts/swift-sources.sh
mkdir -p build
build_stage=$(mktemp -d "$PWD/build/stage.XXXXXX")
app="$build_stage/Remote Vibe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc "${remote_vibe_swift_flags[@]}" -O "${remote_vibe_audio_header[@]}" \
  "${rv_app_sources[@]}" \
  -o "$app/Contents/MacOS/RemoteVibe"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/StatusBar/StatusBar*Template*.png "$app/Contents/Resources/"
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

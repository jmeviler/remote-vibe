#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source Scripts/build-target.sh
mkdir -p build
stage=$(mktemp -d "$PWD/build/driver.XXXXXX")
bundle="$stage/RemoteVibeMic.driver"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun clang -arch "$remote_vibe_arch" -mmacosx-version-min=15.0 -bundle -fblocks -O2 \
  '-DkDriver_Name="RemoteVibeMic"' '-DkPlugIn_BundleID="local.ben.RemoteVibeMic"' \
  '-DkDevice_Name="Chromecast Mic"' -DkHas_Driver_Name_Format=false \
  -DkNumber_Of_Channels=1 -DkSampleRates=48000 -DkEnableVolumeControl=false \
  -DkCanBeDefaultSystemDevice=false \
  Driver/RemoteVibeMic.c -framework CoreAudio -framework CoreFoundation -framework Accelerate \
  -o "$bundle/Contents/MacOS/RemoteVibeMic"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RemoteVibeMic</string>
<key>CFBundleIdentifier</key><string>local.ben.RemoteVibeMic</string>
<key>CFBundleName</key><string>Chromecast Mic</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFPlugInFactories</key><dict><key>128C3E91-D5C5-4AF0-8E71-59C89EA06C63</key><string>BlackHole_Create</string></dict>
<key>CFPlugInTypes</key><dict><key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key><array><string>128C3E91-D5C5-4AF0-8E71-59C89EA06C63</string></array></dict>
</dict></plist>
PLIST
mkdir -p "$bundle/Contents/Resources/Driver" "$bundle/Contents/Resources/Scripts"
cp Driver/LICENSE Driver/SOURCE.md Driver/RemoteVibeMic.c "$bundle/Contents/Resources/Driver/"
cp Scripts/build-driver.sh Scripts/build-target.sh "$bundle/Contents/Resources/Scripts/"
codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --deep --strict "$bundle"
if [[ -d build/RemoteVibeMic.driver ]]; then
  mv build/RemoteVibeMic.driver "build/RemoteVibeMic.previous.$(date +%Y%m%d-%H%M%S).driver"
fi
mv "$bundle" build/RemoteVibeMic.driver
rmdir "$stage"
print 'Built RemoteVibeMic.driver'

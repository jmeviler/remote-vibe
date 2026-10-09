#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p ../build
stage=$(mktemp -d "$PWD/../build/driver.XXXXXX")
bundle="$stage/RemoteVibeMic.driver"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun clang -arch arm64 -mmacosx-version-min=15.0 -bundle -fblocks -O2 \
  '-DkDriver_Name="RemoteVibeMic"' '-DkPlugIn_BundleID="local.ben.RemoteVibeMic"' \
  '-DkDevice_Name="Chromecast Mic"' -DkHas_Driver_Name_Format=false \
  -DkNumber_Of_Channels=1 -DkSampleRates=48000 -DkEnableVolumeControl=false \
  -DkCanBeDefaultSystemDevice=false \
  RemoteVibeMic.c -framework CoreAudio -framework CoreFoundation -framework Accelerate \
  -o "$bundle/Contents/MacOS/RemoteVibeMic"
python3 - "$bundle" <<'PY'
import plistlib,sys
from pathlib import Path
factory='128C3E91-D5C5-4AF0-8E71-59C89EA06C63'
data={'CFBundleExecutable':'RemoteVibeMic','CFBundleIdentifier':'local.ben.RemoteVibeMic',
      'CFBundleName':'Chromecast Mic','CFBundlePackageType':'BNDL','CFBundleVersion':'1',
      'CFBundleShortVersionString':'0.1.0',
      'CFPlugInFactories':{factory:'BlackHole_Create'},
      'CFPlugInTypes':{'443ABAB8-E7B3-491A-B985-BEB9187030DB':[factory]}}
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(data))
PY
cp LICENSE SOURCE.md RemoteVibeMic.c "$bundle/Contents/Resources/"
codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --deep --strict "$bundle"
if [[ -d ../build/RemoteVibeMic.driver ]]; then
  mv ../build/RemoteVibeMic.driver "../build/RemoteVibeMic.previous.$(date +%Y%m%d-%H%M%S).driver"
fi
mv "$bundle" ../build/RemoteVibeMic.driver
rmdir "$stage"
print 'Built RemoteVibeMic.driver'

#!/bin/zsh
set -euo pipefail
(( EUID == 0 )) || { print 'Run with sudo: sudo zsh Scripts/install-driver.sh'; exit 1; }
cd "${0:A:h:h}"
source_bundle="$PWD/build/RemoteVibeMic.driver"
target_bundle="/Library/Audio/Plug-Ins/HAL/RemoteVibeMic.driver"
[[ -d "$source_bundle" ]]
[[ ! -e "$target_bundle" ]] || { print 'Existing driver found; refusing to overwrite.'; exit 1; }
identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$source_bundle/Contents/Info.plist")
[[ "$identifier" == local.ben.RemoteVibeMic ]] || { print 'Unexpected driver identity; stopping.'; exit 1; }
/usr/bin/codesign --verify --deep --strict "$source_bundle"
/usr/bin/ditto "$source_bundle" "$target_bundle"
/usr/sbin/chown -R root:wheel "$target_bundle"
/bin/chmod -R u=rwX,go=rX "$target_bundle"
/usr/bin/codesign --verify --deep --strict "$target_bundle"
/usr/bin/killall coreaudiod || true
print 'Installed Chromecast Mic.'

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
source_bundle="$PWD/build/RemoteVibeMic.driver"
target_bundle="/Library/Audio/Plug-Ins/HAL/RemoteVibeMic.driver"
[[ -d "$source_bundle" ]]
[[ ! -e "$target_bundle" ]] || { print 'Existing driver found; refusing to overwrite.'; exit 1; }
/usr/bin/codesign --verify --deep --strict "$source_bundle"
/usr/bin/ditto "$source_bundle" "$target_bundle"
/usr/sbin/chown -R root:wheel "$target_bundle"
/bin/chmod -R u=rwX,go=rX "$target_bundle"
/usr/bin/codesign --verify --deep --strict "$target_bundle"
/usr/bin/killall coreaudiod || true
print 'Installed Chromecast Mic.'

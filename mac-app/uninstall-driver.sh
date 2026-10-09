#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
target_bundle="/Library/Audio/Plug-Ins/HAL/RemoteVibeMic.driver"
[[ -d "$target_bundle" ]] || { print 'Driver is not installed.'; exit 0; }
identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target_bundle/Contents/Info.plist")
[[ "$identifier" == local.ben.RemoteVibeMic ]] || { print 'Unexpected driver identity; stopping.'; exit 1; }
backup_root="$PWD/build/disabled"
workspace_owner=$(/usr/bin/stat -f '%u:%g' "$PWD")
/bin/mkdir -p "$backup_root"
destination="$backup_root/RemoteVibeMic.$(date +%Y%m%d-%H%M%S).driver"
[[ ! -e "$destination" ]]
/bin/mv "$target_bundle" "$destination"
/usr/sbin/chown -R "$workspace_owner" "$backup_root"
/usr/bin/killall coreaudiod || true
print "Disabled microphone component. Backup: $destination"

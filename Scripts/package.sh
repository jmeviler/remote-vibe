#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ -z "$(git status --porcelain)" ]] || { print -u2 'Commit changes before packaging so bundled source matches the build.'; exit 1; }
app='build/Remote Vibe.app'
driver='build/RemoteVibeMic.driver'
[[ -d "$app" && -d "$driver" ]] || { print -u2 '请先构建 App 和语音组件。'; exit 1; }
[[ "$(cat "$app/Contents/Resources/Source-Commit.txt")" == "$(git rev-parse HEAD)" ]] || { print -u2 'Rebuild the app after committing, then package again.'; exit 1; }
cmp Driver/RemoteVibeMic.c "$driver/Contents/Resources/Driver/RemoteVibeMic.c"
cmp Scripts/build-driver.sh "$driver/Contents/Resources/Scripts/build-driver.sh"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/codesign --verify --deep --strict "$driver"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
stage=$(/usr/bin/mktemp -d "$PWD/build/share.XXXXXX")
name="Remote-Vibe-$version-Mac-AppleSilicon"
share="$stage/$name"
mkdir -p "$share/源码与许可证" "$stage/payload/Applications" "$stage/payload/Library/Audio/Plug-Ins/HAL" "$stage/install-scripts" "$stage/uninstall-scripts" "$stage/resources"
/usr/bin/ditto "$app" "$stage/payload/Applications/Remote Vibe.app"
/usr/bin/ditto "$driver" "$stage/payload/Library/Audio/Plug-Ins/HAL/RemoteVibeMic.driver"
cp Installer/preinstall Installer/postinstall "$stage/install-scripts/"
cp Installer/uninstall "$stage/uninstall-scripts/preinstall"
chmod 755 "$stage/install-scripts/"* "$stage/uninstall-scripts/preinstall"
cp Installer/开始使用.txt "$share/0-开始使用.txt"
cp Installer/Getting-Started.txt "$share/Getting-Started.txt"
cp LICENSE Docs/THIRD_PARTY_NOTICES.md "$share/源码与许可证/"
git archive --format=zip HEAD -o "$share/源码与许可证/remote-vibe-source.zip"
git rev-parse HEAD > "$share/源码与许可证/源代码版本.txt"
/usr/bin/pkgbuild --analyze --root "$stage/payload" "$stage/components.plist"
python3 - "$stage" "$version" <<'PY'
import pathlib, plistlib, sys, html
root = pathlib.Path(sys.argv[1]); version = sys.argv[2]
p = root/'components.plist'
items = plistlib.loads(p.read_bytes())
for item in items:
    item['BundleIsRelocatable'] = False
    item['BundleHasStrictIdentifier'] = True
p.write_bytes(plistlib.dumps(items))
for name, text in [('welcome', 'Remote Vibe '+version+'\n\n支持 M 系列芯片 Mac，macOS 15 或更新。\n支持 Google Chromecast 和小米 RC003 遥控器。\n\n包含 App 和语音组件，无需编译。\n识别依赖微信已有的“长按 Fn 全局语音输入”。\n首次使用仍需本人允许蓝牙、辅助功能等系统权限。\n\n安装会重启系统音频服务，声音可能短暂中断。\n已有旧版时，请先退出 App 并使用配套卸载包。'), ('conclusion', '安装完成\n\n请打开“应用程序 → Remote Vibe”，选择遥控器型号。\n按 App 提示允许权限，然后启用微信长按 Fn 语音输入。\n\n首次使用的完整步骤、常见问题和卸载方法，见压缩包内“0-开始使用.txt”。')]:
    (root/'resources'/f'{name}.html').write_text('<html><head><meta charset="utf-8"></head><body style="font-family: -apple-system; font-size:14px"><pre style="font-family:inherit;white-space:pre-wrap">'+html.escape(text)+'</pre></body></html>')
distribution = f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
 <title>安装 Remote Vibe {version}</title>
 <welcome file="welcome.html" mime-type="text/html"/>
 <conclusion file="conclusion.html" mime-type="text/html"/>
 <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
 <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
 <volume-check><allowed-os-versions><os-version min="15.0"/></allowed-os-versions></volume-check>
 <choices-outline><line choice="main"/></choices-outline>
 <choice id="main" visible="false" title="Remote Vibe 与语音组件"><pkg-ref id="local.ben.RemoteVibe.share"/></choice>
 <pkg-ref id="local.ben.RemoteVibe.share" version="{version}" onConclusion="None">component.pkg</pkg-ref>
</installer-gui-script>'''
(root/'Distribution.xml').write_text(distribution)
PY
/usr/bin/pkgbuild --root "$stage/payload" --component-plist "$stage/components.plist" --scripts "$stage/install-scripts" \
  --identifier local.ben.RemoteVibe.share --version "$version" --install-location / "$stage/component.pkg"
/usr/bin/productbuild --distribution "$stage/Distribution.xml" --resources "$stage/resources" --package-path "$stage" "$share/1-安装 Remote Vibe.pkg"
/usr/bin/pkgbuild --nopayload --scripts "$stage/uninstall-scripts" --identifier local.ben.RemoteVibe.uninstall \
  --version "$version" "$share/2-卸载 Remote Vibe.pkg"
(cd "$share" && /usr/bin/shasum -a 256 *.pkg > SHA256.txt)
mkdir -p build/share
archive="$PWD/build/share/$name.zip"
[[ ! -e "$archive" ]] || { print -u2 "Already exists: $archive"; exit 1; }
python3 - "$share" "$archive" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
# Set ZIP's standard UTF-8 flag so Chinese names also survive non-Apple unzip tools.
with zipfile.ZipFile(sys.argv[2], 'x', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob('*')):
        if path.is_file():
            archive.write(path, str(path.relative_to(root.parent)))
PY
print "Share archive: $archive"
print "Staging directory: $stage"

# App-only updates preserve the installed audio driver and avoid restarting audio.
update="$stage/app-update"
mkdir -p "$update"
/usr/bin/ditto "$app" "$update/Remote Vibe.app"
cp Installer/Update-README.txt "$update/Update-README.txt"
git rev-parse HEAD > "$update/Source-Commit.txt"
update_archive="$PWD/build/share/Remote-Vibe-$version-App-AppleSilicon.zip"
[[ ! -e "$update_archive" ]] || { print -u2 "Already exists: $update_archive"; exit 1; }
/usr/bin/ditto -c -k "$update" "$update_archive"
(cd build/share && /usr/bin/shasum -a 256 "${archive:t}" "${update_archive:t}" > SHA256SUMS.txt)
print "App update archive: $update_archive"

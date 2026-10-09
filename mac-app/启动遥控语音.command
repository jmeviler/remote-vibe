#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="$PWD/build/Remote Vibe.app"
[[ -d "$app" ]] || { print '应用文件未找到，请联系维护者恢复已验证版本。'; exit 1; }
/usr/bin/open "$app"

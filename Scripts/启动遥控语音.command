#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/build/Remote Vibe.app"
[[ -d "$app" ]] || { print '请先在项目根目录运行：zsh Scripts/build-app.sh'; exit 1; }
/usr/bin/open "$app"

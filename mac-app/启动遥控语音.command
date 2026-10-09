#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="$PWD/build/Remote Vibe.app"
[[ -d "$app" ]] || { print '请先在 mac-app 目录运行：zsh build.sh'; exit 1; }
/usr/bin/open "$app"

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
source Scripts/swift-sources.sh
mkdir -p build/tests
xcrun swiftc "${remote_vibe_swift_flags[@]}" \
  "${rv_bluetooth_timers_sources[@]}" Tests/bluetooth_timers_test.swift \
  -o build/tests/bluetooth-timers
build/tests/bluetooth-timers

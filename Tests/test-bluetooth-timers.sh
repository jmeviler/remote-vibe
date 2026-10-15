#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -warnings-as-errors -target "$remote_vibe_swift_target" \
  Sources/Bluetooth/BluetoothTimers.swift Tests/bluetooth_timers_test.swift \
  -o build/tests/bluetooth-timers
build/tests/bluetooth-timers

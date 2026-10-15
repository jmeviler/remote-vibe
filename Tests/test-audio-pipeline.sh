#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -warnings-as-errors -target "$remote_vibe_swift_target" \
  Sources/Audio/VirtualMicrophone.swift Sources/Audio/VoiceSessionTiming.swift Tests/audio_pipeline_test.swift \
  -o build/tests/audio-pipeline
build/tests/audio-pipeline
xcrun clang -arch "$remote_vibe_arch" -mmacosx-version-min=15.0 -fblocks -O2 \
  Tests/driver_test.c -framework CoreAudio -framework CoreFoundation -framework Accelerate \
  -o build/tests/driver
build/tests/driver

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
source Scripts/swift-sources.sh
mkdir -p build/tests
xcrun swiftc "${remote_vibe_swift_flags[@]}" "${remote_vibe_audio_header[@]}" \
  "${rv_audio_pipeline_sources[@]}" Tests/audio_pipeline_test.swift \
  -o build/tests/audio-pipeline
build/tests/audio-pipeline
xcrun clang -arch "$remote_vibe_arch" -mmacosx-version-min=15.0 -fblocks -O2 \
  Tests/driver_test.c -framework CoreAudio -framework CoreFoundation -framework Accelerate \
  -o build/tests/driver
build/tests/driver

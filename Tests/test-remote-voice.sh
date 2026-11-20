#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
source Scripts/swift-sources.sh
mkdir -p build/tests
xcrun swiftc "${remote_vibe_swift_flags[@]}" \
  "${rv_remote_voice_sources[@]}" Tests/remote_audio_session_test.swift \
  -o build/tests/remote-audio-session
build/tests/remote-audio-session

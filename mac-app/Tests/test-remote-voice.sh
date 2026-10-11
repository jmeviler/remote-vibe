#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/RemoteProfile.swift Sources/BridgeError.swift Sources/ADPCMDecoder.swift \
  Sources/ATVVProtocol.swift Sources/RemoteAudioSession.swift Tests/remote_audio_session_test.swift \
  -o build/tests/remote-audio-session
build/tests/remote-audio-session

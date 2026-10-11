#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 \
  Sources/App/Localization.swift Sources/Bluetooth/RemoteProfile.swift Sources/Bluetooth/ATVVError.swift Sources/Audio/ADPCMDecoder.swift \
  Sources/Bluetooth/ATVVProtocol.swift Sources/Audio/RemoteAudioSession.swift Tests/remote_audio_session_test.swift \
  -o build/tests/remote-audio-session
build/tests/remote-audio-session

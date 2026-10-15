#!/bin/zsh
# Shared by the cloud build, tests and packaging; default to the runner's native CPU.
remote_vibe_arch="${REMOTE_VIBE_ARCH:-$(/usr/bin/uname -m)}"
case "$remote_vibe_arch" in
  arm64) remote_vibe_chip=AppleSilicon ;;
  x86_64) remote_vibe_chip=Intel ;;
  *) print -u2 "Unsupported Remote Vibe architecture: $remote_vibe_arch"; exit 1 ;;
esac
remote_vibe_swift_target="${remote_vibe_arch}-apple-macos15.0"

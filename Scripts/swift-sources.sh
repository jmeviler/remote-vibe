#!/bin/zsh
# Centralized Swift compiler flags and module source lists for app builds and isolated tests.

remote_vibe_swift_flags=(-swift-version 5 -parse-as-library -warnings-as-errors -target "$remote_vibe_swift_target")
remote_vibe_audio_header=(-import-objc-header Sources/Audio/AudioRingBuffer.h)

rv_app_support_sources=(
  Sources/App/Localization.swift
  Sources/App/ReleaseUpdate.swift
  Sources/App/StatusWriter.swift
  Sources/App/LaunchAtLogin.swift
  Sources/Bluetooth/RemoteProfile.swift
)

rv_bluetooth_timers_sources=(
  Sources/Bluetooth/BluetoothTimers.swift
)

rv_audio_pipeline_sources=(
  Sources/Audio/VirtualMicrophone.swift
  Sources/Audio/VoiceSessionTiming.swift
)

rv_protocol_sources=(
  Sources/App/Localization.swift
  Sources/Bluetooth/RemoteProfile.swift
  Sources/Bluetooth/ATVVError.swift
  Sources/Audio/ADPCMDecoder.swift
  Sources/Bluetooth/ATVVProtocol.swift
)

rv_remote_voice_sources=(
  "${rv_protocol_sources[@]}"
  Sources/Audio/RemoteAudioSession.swift
)

rv_input_sources=(
  Sources/App/Localization.swift
  Sources/Bluetooth/RemoteProfile.swift
  Sources/Bluetooth/ATVVError.swift
  Sources/Input/FnKey.swift
  Sources/Input/VoiceTrigger.swift
  Sources/Input/MousePointer.swift
  Sources/Input/DesktopActions.swift
  Sources/Input/ClipboardPaste.swift
  Sources/Input/ButtonGesture.swift
  Sources/Input/ActionCatalog.swift
  Sources/Input/KeyMapping.swift
  Sources/Input/MappingStore.swift
)

rv_ui_mapping_sources=(
  Sources/UI/SettingsUI.swift
  Sources/UI/ShortcutRecorderView.swift
  Sources/UI/VoiceStudioView.swift
  Sources/UI/KeyMappingView.swift
)

rv_app_sources=(
  "${rv_remote_voice_sources[@]}"
  "${rv_bluetooth_timers_sources[@]}"
  Sources/Bluetooth/BluetoothRemote.swift
  Sources/Bluetooth/RemoteController.swift
  Sources/Input/XiaomiVoiceKeyOverride.swift
  "${rv_audio_pipeline_sources[@]}"
  Sources/Input/FnKey.swift
  Sources/Input/VoiceTrigger.swift
  Sources/Input/MousePointer.swift
  Sources/Input/DesktopActions.swift
  Sources/Input/ClipboardPaste.swift
  Sources/Input/ButtonGesture.swift
  Sources/Input/ActionCatalog.swift
  Sources/Input/KeyMapping.swift
  Sources/Input/MappingStore.swift
  "${rv_ui_mapping_sources[@]}"
  Sources/Unlock/ComboUnlock.swift
  Sources/UI/ComboUnlockView.swift
  Sources/UI/StatusBarIcon.swift
  Sources/App/ReleaseUpdate.swift
  Sources/App/StatusWriter.swift
  Sources/App/LaunchAtLogin.swift
  Sources/App/AppController.swift
)

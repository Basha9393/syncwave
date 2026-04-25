#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/build/SyncWaveDesktopApp"

mkdir -p "$ROOT_DIR/build"

swiftc \
  "$ROOT_DIR/App/SyncWaveApp.swift" \
  "$ROOT_DIR/App/Views/RoleSelectionView.swift" \
  "$ROOT_DIR/App/ViewModels/RoleViewModel.swift" \
  "$ROOT_DIR/App/ViewModels/MetricsViewModel.swift" \
  "$ROOT_DIR/App/Runtime/SyncWaveTypes.swift" \
  "$ROOT_DIR/App/Runtime/SenderService.swift" \
  "$ROOT_DIR/App/Runtime/ReceiverService.swift" \
  "$ROOT_DIR/App/Config/SettingsStore.swift" \
  "$ROOT_DIR/App/Network/DiscoveryService.swift" \
  "$ROOT_DIR/Sources/SyncWaveSender/RTPSender.swift" \
  "$ROOT_DIR/Sources/SyncWaveSender/AudioTap.swift" \
  "$ROOT_DIR/Sources/SyncWaveReceiver/RTPReceiver.swift" \
  "$ROOT_DIR/Sources/SyncWaveReceiver/AudioPlayer.swift" \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreAudio \
  -o "$OUTPUT"

echo "Built desktop app executable: $OUTPUT"

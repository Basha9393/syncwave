// SyncWaveSender — Host Mac
// Captures system audio and streams it over RTP/UDP multicast
//
// STATUS: Skeleton only. Not yet implemented.
// Start with AudioTap.swift (Phase 1 in ROADMAP.md)

import Foundation
import AVFoundation
import CoreAudio

// MARK: - Entry point

print("SyncWave Sender starting...")
print("Multicast group: 239.0.0.1:5004")
print("Codec: Opus 48kHz stereo, 10ms frames")

// Pipeline (to be wired up):
//
//   AudioTap
//     │  PCM buffers (Float32, 48kHz, stereo)
//     ▼
//   OpusEncoder
//     │  Encoded frames (~160 bytes per 10ms)
//     ▼
//   RTPSender
//     │  RTP packets (header + Opus payload)
//     ▼
//   UDP multicast socket → LAN

// TODO Phase 1: let tap = AudioTap()
// TODO Phase 2: let encoder = OpusEncoder(sampleRate: 48000, channels: 2, frameDuration: .ms10)
// TODO Phase 3: let sender = RTPSender(multicastGroup: "239.0.0.1", port: 5004)

// TODO: wire up: tap.onBuffer = { pcm in encoder.encode(pcm) { opus in sender.send(opus) } }
// TODO: tap.start()

// Keep the process alive
RunLoop.main.run()

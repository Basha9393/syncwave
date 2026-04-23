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

let sender = RTPSender(multicastGroup: "239.0.0.1", port: 5004, samplesPerFrame: 480)
var sentPacketCount: UInt64 = 0

// Temporary bootstrap path:
// Until AudioTap + Opus are implemented, send synthetic frames at 10ms cadence so
// transport can be validated independently.
Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { _ in
    var payload = Data(count: 160)
    payload.withUnsafeMutableBytes { rawBuffer in
        guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
        for i in 0..<160 {
            bytes[i] = UInt8((Int(sentPacketCount) + i) % 256)
        }
    }
    sender.send(payload)
    sentPacketCount += 1
    if sentPacketCount.isMultiple(of: 100) {
        print("[Sender] sent \(sentPacketCount) RTP packets")
    }
}

// Keep the process alive
RunLoop.main.run()

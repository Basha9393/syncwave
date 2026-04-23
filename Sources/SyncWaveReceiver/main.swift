// SyncWaveReceiver — Receiver Mac
// Listens for RTP/UDP multicast packets and plays audio in sync.
//
// STATUS: Skeleton only. Not yet implemented.
// Follow ROADMAP.md Phase 4 then Phase 5.

import Foundation
import AVFoundation

print("SyncWave Receiver starting...")
print("Listening on multicast: 239.0.0.1:5004")
print("Jitter buffer: 20ms")

// Pipeline (to be wired up):
//
//   RTPReceiver (UDP socket)
//     │  RTP packets arriving from network
//     ▼
//   JitterBuffer (20ms)
//     │  Packets sorted by sequence number, held until play time
//     ▼
//   OpusDecoder
//     │  PCM Float32 buffers
//     ▼
//   AudioPlayer (AVAudioPlayerNode)
//     │  Scheduled at exact AVAudioTime from RTP timestamp
//     ▼
//   System speakers

let receiver = RTPReceiver(multicastGroup: "239.0.0.1", port: 5004)
var receivedPacketCount: UInt64 = 0
var windowPacketCount: UInt64 = 0
var windowStart = Date()

receiver.onPacket = { packet in
    receivedPacketCount += 1
    windowPacketCount += 1
    if receivedPacketCount.isMultiple(of: 100) {
        let now = Date()
        let windowElapsed = now.timeIntervalSince(windowStart)
        let instantRate = windowElapsed > 0 ? Double(windowPacketCount) / windowElapsed : 0
        print("[Receiver] packets=\(receivedPacketCount) rate=\(String(format: "%.1f", instantRate))/s seq=\(packet.sequenceNumber) payload=\(packet.payload.count)B")
        windowPacketCount = 0
        windowStart = now
    }
}

receiver.onError = { message in
    print(message)
}
// TODO Phase 4: let decoder = OpusDecoder(sampleRate: 48000, channels: 2)
// TODO Phase 4: let player = AudioPlayer()
// TODO Phase 5: let jitterBuffer = JitterBuffer(targetLatencyMs: 20)

// TODO: wire up pipeline
receiver.start()

RunLoop.main.run()

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
print("Playback mode: bootstrap PCM16 mono tone -> stereo output")

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
let expectedPacketIntervalSec = 0.010
let hostTicksPerSecond = receiverMachTicksPerSecond()
let pcmFrameSamples = 480
let pcmBytesPerFrame = pcmFrameSamples * MemoryLayout<Int16>.size
let playbackQueue = DispatchQueue(label: "com.syncwave.playback", qos: .userInitiated)

let player = AudioPlayer()
do {
    try player.setup(sampleRate: 48_000, channels: 2)
} catch {
    print("[Receiver] AudioPlayer setup failed: \(error.localizedDescription)")
}

var lastSequenceNumber: UInt16?
var lastReceivedAtTicks: UInt64?
var estimatedJitterSec: Double = 0
var lostPacketCount: UInt64 = 0
var reorderedPacketCount: UInt64 = 0
var duplicatePacketCount: UInt64 = 0

receiver.onPacket = { packet in
    receivedPacketCount += 1
    windowPacketCount += 1

    if let lastSeq = lastSequenceNumber {
        let seqDelta = packet.sequenceNumber &- lastSeq
        if seqDelta == 0 {
            duplicatePacketCount += 1
        } else if seqDelta == 1 {
            // In-order packet, no accounting updates needed.
        } else if seqDelta < 0x8000 {
            lostPacketCount += UInt64(seqDelta - 1)
        } else {
            reorderedPacketCount += 1
        }
    }
    lastSequenceNumber = packet.sequenceNumber

    if let previousTicks = lastReceivedAtTicks {
        let interArrivalSec = Double(packet.receivedAt &- previousTicks) / hostTicksPerSecond
        let deviation = abs(interArrivalSec - expectedPacketIntervalSec)
        estimatedJitterSec += (deviation - estimatedJitterSec) / 16.0
    }
    lastReceivedAtTicks = packet.receivedAt

    if packet.payload.count == pcmBytesPerFrame, let buffer = makeStereoBufferFromMonoPCM16(packet.payload) {
        playbackQueue.async {
            player.play(buffer: buffer)
        }
    }

    if receivedPacketCount.isMultiple(of: 100) {
        let now = Date()
        let windowElapsed = now.timeIntervalSince(windowStart)
        let instantRate = windowElapsed > 0 ? Double(windowPacketCount) / windowElapsed : 0
        let jitterMs = estimatedJitterSec * 1000.0
        let lossPct = receivedPacketCount > 0 ? (Double(lostPacketCount) / Double(receivedPacketCount + lostPacketCount)) * 100.0 : 0
        print("[Receiver] packets=\(receivedPacketCount) rate=\(String(format: "%.1f", instantRate))/s seq=\(packet.sequenceNumber) payload=\(packet.payload.count)B loss=\(lostPacketCount) (\(String(format: "%.2f", lossPct))%) reorder=\(reorderedPacketCount) dup=\(duplicatePacketCount) jitter=\(String(format: "%.2f", jitterMs))ms")
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

private func receiverMachTicksPerSecond() -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return 1e9 * Double(info.denom) / Double(info.numer)
}

private func makeStereoBufferFromMonoPCM16(_ payload: Data) -> AVAudioPCMBuffer? {
    let frameCount = payload.count / MemoryLayout<Int16>.size
    guard frameCount > 0 else { return nil }

    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
          let left = buffer.floatChannelData?[0],
          let right = buffer.floatChannelData?[1] else {
        return nil
    }

    buffer.frameLength = AVAudioFrameCount(frameCount)
    payload.withUnsafeBytes { rawBuffer in
        let samples = rawBuffer.bindMemory(to: Int16.self)
        guard let base = samples.baseAddress else { return }
        for i in 0..<frameCount {
            let value = Float(Int16(littleEndian: base[i])) / Float(Int16.max)
            left[i] = value
            right[i] = value
        }
    }
    return buffer
}

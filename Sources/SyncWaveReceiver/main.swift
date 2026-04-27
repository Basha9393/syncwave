// SyncWaveReceiver — Receiver Mac
// Listens for RTP/UDP multicast packets and plays audio in sync.
//
// STATUS: Skeleton only. Not yet implemented.
// Follow ROADMAP.md Phase 4 then Phase 5.

import Foundation
import AVFoundation

struct ReceiverCLIConfig {
    var transport: RTPReceiver.TransportMode = .multicast
    var host: String = "239.0.0.1"
    var port: UInt16 = 5004
}

let receiverConfig = parseReceiverCLIConfig(CommandLine.arguments)

print("SyncWave Receiver starting...")
print("Transport: \(receiverConfig.transport)")
print("Listening target: \(receiverConfig.host):\(receiverConfig.port)")
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

let receiver = RTPReceiver(listenAddress: receiverConfig.host, port: receiverConfig.port, transportMode: receiverConfig.transport)
var receivedPacketCount: UInt64 = 0
var windowPacketCount: UInt64 = 0
var windowStart = Date()
let expectedPacketIntervalSec = 0.010
let hostTicksPerSecond = receiverMachTicksPerSecond()
let pcmFrameSamples = 480
let pcmBytesPerFrame = pcmFrameSamples * MemoryLayout<Int16>.size
let playbackQueue = DispatchQueue(label: "com.syncwave.playback", qos: .userInitiated)
let targetPrebufferPackets = 3
let silencePayload = Data(count: pcmBytesPerFrame)

let player = AudioPlayer()
do {
    try player.setup(sampleRate: 48_000, channels: 2)
} catch {
    print("[Receiver] AudioPlayer setup failed: \(error.localizedDescription)")
}

let opusDecoder = OpusDecoder(sampleRate: 48_000, channels: 1)

var lastSequenceNumber: UInt16?
var lastReceivedAtTicks: UInt64?
var estimatedJitterSec: Double = 0
var lostPacketCount: UInt64 = 0
var reorderedPacketCount: UInt64 = 0
var duplicatePacketCount: UInt64 = 0
var streamSSRC: UInt32?
var concealmentFrameCount: UInt64 = 0

var jitterBuffer: [UInt16: Data] = [:]
var expectedPlayoutSequence: UInt16?
var lastGoodPayload: Data?

let playbackTimer = DispatchSource.makeTimerSource(queue: playbackQueue)
playbackTimer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(10), leeway: .milliseconds(2))
playbackTimer.setEventHandler {
    if expectedPlayoutSequence == nil {
        guard jitterBuffer.count >= targetPrebufferPackets else { return }
        expectedPlayoutSequence = jitterBuffer.keys.min()
    }

    guard let seq = expectedPlayoutSequence else { return }

    let opusData: Data?
    if let payload = jitterBuffer.removeValue(forKey: seq) {
        opusData = payload
        lastGoodPayload = payload
    } else {
        // Packet loss: use Opus PLC if available, else silence
        concealmentFrameCount += 1
        opusData = lastGoodPayload
    }

    // Decode Opus to PCM
    if let opusData = opusData, let decodedFloat32 = opusDecoder.decode(opusData) {
        // Convert Float32 mono to stereo
        if let stereoBuffer = makeStereoBufferFromMonoFloat32(decodedFloat32) {
            player.play(buffer: stereoBuffer)
        }
    } else if let lastGood = lastGoodPayload, let decodedFloat32 = opusDecoder.decode(lastGood) {
        // Fallback: play last known good frame
        if let stereoBuffer = makeStereoBufferFromMonoFloat32(decodedFloat32) {
            player.play(buffer: stereoBuffer)
        }
    }

    expectedPlayoutSequence = seq &+ 1

    if jitterBuffer.count > 500, let oldest = jitterBuffer.keys.min() {
        jitterBuffer.removeValue(forKey: oldest)
    }
}
playbackTimer.resume()

receiver.onPacket = { packet in
    if streamSSRC != packet.ssrc {
        if streamSSRC != nil {
            print("[Receiver] stream changed, resetting stats. oldSSRC=\(streamSSRC!) newSSRC=\(packet.ssrc)")
        }
        streamSSRC = packet.ssrc
        receivedPacketCount = 0
        windowPacketCount = 0
        windowStart = Date()
        lastSequenceNumber = nil
        lastReceivedAtTicks = nil
        estimatedJitterSec = 0
        lostPacketCount = 0
        reorderedPacketCount = 0
        duplicatePacketCount = 0
        concealmentFrameCount = 0
        playbackQueue.async {
            jitterBuffer.removeAll(keepingCapacity: true)
            expectedPlayoutSequence = nil
            lastGoodPayload = nil
        }
    }

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

    if packet.payload.count == pcmBytesPerFrame {
        playbackQueue.async {
            jitterBuffer[packet.sequenceNumber] = packet.payload
        }
    }

    if receivedPacketCount.isMultiple(of: 100) {
        let now = Date()
        let windowElapsed = now.timeIntervalSince(windowStart)
        let instantRate = windowElapsed > 0 ? Double(windowPacketCount) / windowElapsed : 0
        let jitterMs = estimatedJitterSec * 1000.0
        let lossPct = receivedPacketCount > 0 ? (Double(lostPacketCount) / Double(receivedPacketCount + lostPacketCount)) * 100.0 : 0
        print("[Receiver] packets=\(receivedPacketCount) rate=\(String(format: "%.1f", instantRate))/s seq=\(packet.sequenceNumber) payload=\(packet.payload.count)B loss=\(lostPacketCount) (\(String(format: "%.2f", lossPct))%) reorder=\(reorderedPacketCount) dup=\(duplicatePacketCount) conceal=\(concealmentFrameCount) jitter=\(String(format: "%.2f", jitterMs))ms")
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

private func makeStereoBufferFromMonoFloat32(_ mono: [Float]) -> AVAudioPCMBuffer? {
    let frameCount = mono.count
    guard frameCount > 0 else { return nil }

    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
          let left = buffer.floatChannelData?[0],
          let right = buffer.floatChannelData?[1] else {
        return nil
    }

    buffer.frameLength = AVAudioFrameCount(frameCount)
    for i in 0..<frameCount {
        let value = max(-1.0, min(1.0, mono[i]))  // Clamp to [-1, 1]
        left[i] = value
        right[i] = value
    }
    return buffer
}

private func parseReceiverCLIConfig(_ args: [String]) -> ReceiverCLIConfig {
    var config = ReceiverCLIConfig()
    var idx = 1
    while idx < args.count {
        switch args[idx] {
        case "--transport":
            guard idx + 1 < args.count else {
                print("[Receiver] Missing value for --transport")
                idx += 1
                continue
            }
            let value = args[idx + 1].lowercased()
            if value == "unicast" {
                config.transport = .unicast
                config.host = "0.0.0.0"
            } else {
                config.transport = .multicast
                config.host = "239.0.0.1"
            }
            idx += 2
        case "--host":
            guard idx + 1 < args.count else {
                print("[Receiver] Missing value for --host")
                idx += 1
                continue
            }
            config.host = args[idx + 1]
            idx += 2
        case "--port":
            guard idx + 1 < args.count else {
                print("[Receiver] Missing value for --port")
                idx += 1
                continue
            }
            if let port = UInt16(args[idx + 1]) {
                config.port = port
            } else {
                print("[Receiver] Invalid --port value: \(args[idx + 1])")
            }
            idx += 2
        default:
            idx += 1
        }
    }
    return config
}

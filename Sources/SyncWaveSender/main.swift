// SyncWaveSender — Host Mac
// Captures system audio and streams it over RTP/UDP multicast
//
// STATUS: Skeleton only. Not yet implemented.
// Start with AudioTap.swift (Phase 1 in ROADMAP.md)

import Foundation
import AVFoundation
import CoreAudio

struct SenderCLIConfig {
    var transport: RTPSender.TransportMode = .multicast
    var host: String = "239.0.0.1"
    var port: UInt16 = 5004
}

let senderConfig = parseSenderCLIConfig(CommandLine.arguments)

// MARK: - Entry point

print("SyncWave Sender starting...")
print("Transport: \(senderConfig.transport)")
print("Target: \(senderConfig.host):\(senderConfig.port)")
print("Codec: bootstrap PCM16 mono tone, 10ms frames")

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

let sender = RTPSender(
    targetHost: senderConfig.host,
    port: senderConfig.port,
    samplesPerFrame: 480,
    transportMode: senderConfig.transport
)
var sentPacketCount: UInt64 = 0
let sampleRate: Double = 48_000
let frameSamples = 480
let toneFrequencyHz: Double = 440.0
let amplitude: Double = 0.20
var phase: Double = 0
let phaseStep = (2.0 * Double.pi * toneFrequencyHz) / sampleRate

// Temporary bootstrap path:
// Until AudioTap + Opus are implemented, send a PCM16 mono tone at 10ms cadence.
// This validates transport + playback end-to-end without RTP payload fragmentation.
Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { _ in
    var payload = Data(count: frameSamples * MemoryLayout<Int16>.size)
    payload.withUnsafeMutableBytes { rawBuffer in
        let samples = rawBuffer.bindMemory(to: Int16.self)
        guard let baseAddress = samples.baseAddress else { return }
        for i in 0..<frameSamples {
            let sampleValue = sin(phase) * amplitude
            let pcm = Int16(max(-1.0, min(1.0, sampleValue)) * Double(Int16.max))
            baseAddress[i] = pcm.littleEndian
            phase += phaseStep
            if phase >= 2.0 * Double.pi {
                phase -= 2.0 * Double.pi
            }
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

private func parseSenderCLIConfig(_ args: [String]) -> SenderCLIConfig {
    var config = SenderCLIConfig()
    var idx = 1
    while idx < args.count {
        switch args[idx] {
        case "--transport":
            guard idx + 1 < args.count else {
                print("[Sender] Missing value for --transport")
                idx += 1
                continue
            }
            let value = args[idx + 1].lowercased()
            if value == "unicast" {
                config.transport = .unicast
                config.host = "127.0.0.1"
            } else {
                config.transport = .multicast
                config.host = "239.0.0.1"
            }
            idx += 2
        case "--host":
            guard idx + 1 < args.count else {
                print("[Sender] Missing value for --host")
                idx += 1
                continue
            }
            config.host = args[idx + 1]
            idx += 2
        case "--port":
            guard idx + 1 < args.count else {
                print("[Sender] Missing value for --port")
                idx += 1
                continue
            }
            if let port = UInt16(args[idx + 1]) {
                config.port = port
            } else {
                print("[Sender] Invalid --port value: \(args[idx + 1])")
            }
            idx += 2
        default:
            idx += 1
        }
    }
    return config
}

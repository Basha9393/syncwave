// SyncWaveSender — Host Mac
// Captures system audio and streams it over RTP/UDP multicast
//
// STATUS: Skeleton only. Not yet implemented.
// Start with AudioTap.swift (Phase 1 in ROADMAP.md)

import Foundation
import AVFoundation
import CoreAudio

struct SenderCLIConfig {
    enum SourceMode: CustomStringConvertible {
        case tone
        case tap

        var description: String {
            switch self {
            case .tone: return "tone"
            case .tap: return "tap"
            }
        }
    }

    var transport: RTPSender.TransportMode = .multicast
    var host: String = "239.0.0.1"
    var port: UInt16 = 5004
    var source: SourceMode = .tone
}

let senderConfig = parseSenderCLIConfig(CommandLine.arguments)

// MARK: - Entry point

print("SyncWave Sender starting...")
print("Transport: \(senderConfig.transport)")
print("Target: \(senderConfig.host):\(senderConfig.port)")
print("Source: \(senderConfig.source)")
print("Payload: PCM16 mono, 10ms frames")

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

let opusEncoder = OpusEncoder(sampleRate: 48000, channels: 1, frameDuration: .ms10, bitrate: 128_000)

var sentPacketCount: UInt64 = 0
let sampleRate: Double = 48_000
let frameSamples = 480
let toneFrequencyHz: Double = 440.0
let amplitude: Double = 0.20
var phase: Double = 0
let phaseStep = (2.0 * Double.pi * toneFrequencyHz) / sampleRate
var tapKeeper: AudioTap?

switch senderConfig.source {
case .tone:
    // Bootstrap mode used for transport/playback validation.
    // Generates a 440Hz sine wave, encodes to Opus, and streams it.
    Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { _ in
        // Generate Float32 PCM samples
        var pcmSamples = [Float](repeating: 0, count: frameSamples)
        for i in 0..<frameSamples {
            let sampleValue = sin(phase) * amplitude
            pcmSamples[i] = Float(max(-1.0, min(1.0, sampleValue)))
            phase += phaseStep
            if phase >= 2.0 * Double.pi {
                phase -= 2.0 * Double.pi
            }
        }

        // Encode to Opus
        if let opusFrame = opusEncoder.encode(pcmSamples) {
            sender.send(opusFrame)
            sentPacketCount += 1
            if sentPacketCount.isMultiple(of: 100) {
                print("[Sender] sent \(sentPacketCount) Opus RTP packets")
            }
        } else {
            print("[Sender] Opus encoding failed")
        }
    }

case .tap:
    // Phase 1 integration path: stream captured PCM from AudioTap.
    let tap = AudioTap()
    var pendingMonoSamples: [Float] = []
    tap.onBuffer = { buffer in
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return }

        for frameIndex in 0..<frameCount {
            var mixed: Float = 0
            for channel in 0..<channelCount {
                mixed += channelData[channel][frameIndex]
            }
            pendingMonoSamples.append(mixed / Float(channelCount))
        }

        while pendingMonoSamples.count >= frameSamples {
            let frameSamples = Array(pendingMonoSamples.prefix(frameSamples))
            pendingMonoSamples.removeFirst(frameSamples.count)

            // Encode to Opus
            if let opusFrame = opusEncoder.encode(frameSamples) {
                sender.send(opusFrame)
                sentPacketCount += 1
                if sentPacketCount.isMultiple(of: 100) {
                    print("[Sender] sent \(sentPacketCount) Opus RTP packets (from tap)")
                }
            }
        }
    }
    tap.start()
    print("[Sender] tap mode active (capturing system audio)")
    tapKeeper = tap
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
        case "--source":
            guard idx + 1 < args.count else {
                print("[Sender] Missing value for --source")
                idx += 1
                continue
            }
            let value = args[idx + 1].lowercased()
            config.source = value == "tap" ? .tap : .tone
            idx += 2
        default:
            idx += 1
        }
    }
    return config
}

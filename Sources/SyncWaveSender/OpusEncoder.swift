// OpusEncoder.swift
// Wraps libopus to encode PCM audio buffers into Opus frames.
//
// STATUS: Skeleton with implementation notes. Phase 2 of ROADMAP.md.
//
// Prerequisites:
//   brew install opus
//   Add libopus to your Xcode project:
//     - Option A: Use a bridging header pointing to /opt/homebrew/include/opus/opus.h
//     - Option B: Create a Swift Package with a C target wrapping libopus
//     - Option C: Use a pre-built xcframework (search GitHub for "opus xcframework")

import Foundation

// MARK: - Frame duration

enum OpusFrameDuration {
    case ms2_5, ms5, ms10, ms20, ms40, ms60

    var sampleCount: Int {
        // At 48kHz sample rate
        switch self {
        case .ms2_5: return 120
        case .ms5:   return 240
        case .ms10:  return 480
        case .ms20:  return 960
        case .ms40:  return 1920
        case .ms60:  return 2880
        }
    }
}

// MARK: - OpusEncoder

/// Encodes Float32 PCM audio to Opus frames using libopus.
///
/// Recommended settings for music streaming:
///   sampleRate: 48000 (Opus native rate)
///   channels: 2
///   frameDuration: .ms10 (10ms frames = good latency/quality balance)
///   bitrate: 128000 (128kbps = transparent quality for stereo music)
class OpusEncoder {

    let sampleRate: Int
    let channels: Int
    let frameDuration: OpusFrameDuration
    let bitrate: Int

    // MARK: - Implementation notes
    //
    // With a bridging header that imports <opus/opus.h>:
    //
    //   var error: Int32 = 0
    //   let encoder = opus_encoder_create(
    //       Int32(sampleRate),
    //       Int32(channels),
    //       OPUS_APPLICATION_AUDIO,   // use AUDIO not VOIP — better for music
    //       &error
    //   )
    //   guard error == OPUS_OK else { fatalError("Opus init failed: \(error)") }
    //   opus_encoder_ctl(encoder, OPUS_SET_BITRATE(Int32(bitrate)))
    //
    // Encoding:
    //   let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4000)
    //   let frameSize = Int32(frameDuration.sampleCount)
    //
    //   pcmBuffer.withUnsafeBytes { pcmPtr in
    //       let floatPtr = pcmPtr.bindMemory(to: Float.self).baseAddress!
    //       let encodedBytes = opus_encode_float(encoder, floatPtr, frameSize, outputBuffer, 4000)
    //       // encodedBytes is the number of bytes written to outputBuffer
    //       let opusData = Data(bytes: outputBuffer, count: Int(encodedBytes))
    //       callback(opusData)
    //   }
    //
    // Note: Opus expects interleaved stereo samples: [L, R, L, R, ...]
    // AVAudioPCMBuffer may give you separate channel buffers — interleave before encoding.

    init(sampleRate: Int = 48000, channels: Int = 2, frameDuration: OpusFrameDuration = .ms10, bitrate: Int = 128_000) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.frameDuration = frameDuration
        self.bitrate = bitrate
        print("[OpusEncoder] init — not yet implemented. sampleRate=\(sampleRate) channels=\(channels) frameDuration=\(frameDuration) bitrate=\(bitrate)")
    }

    /// Encode a PCM buffer to an Opus frame.
    /// - Parameter pcm: Raw Float32 interleaved PCM samples (exactly frameDuration.sampleCount * channels samples)
    /// - Returns: Encoded Opus frame bytes, or nil on error
    func encode(_ pcm: [Float]) -> Data? {
        // TODO: implement per notes above
        return nil
    }

    deinit {
        // TODO: opus_encoder_destroy(encoder)
    }
}

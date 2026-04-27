// OpusEncoder.swift
// Wraps libopus to encode PCM audio buffers into Opus frames.
//
// Phase 2 of ROADMAP.md.

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
    private var encoder: OpaquePointer?

    init(sampleRate: Int = 48000, channels: Int = 2, frameDuration: OpusFrameDuration = .ms10, bitrate: Int = 128_000) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.frameDuration = frameDuration
        self.bitrate = bitrate

        // Create encoder
        var error: Int32 = 0
        let enc = opus_encoder_create(
            Int32(sampleRate),
            Int32(channels),
            OPUS_APPLICATION_AUDIO,  // Use AUDIO not VOIP — better for music
            &error
        )

        guard error == OPUS_OK, let enc = enc else {
            print("[OpusEncoder] init failed: error code \(error)")
            return
        }

        // Set bitrate
        let bitrateResult = opus_encoder_ctl(enc, OPUS_SET_BITRATE(Int32(bitrate)))
        guard bitrateResult == OPUS_OK else {
            print("[OpusEncoder] failed to set bitrate: \(bitrateResult)")
            opus_encoder_destroy(enc)
            return
        }

        self.encoder = enc
        print("[OpusEncoder] initialized. sampleRate=\(sampleRate)Hz channels=\(channels) bitrate=\(bitrate)bps")
    }

    /// Encode a PCM buffer to an Opus frame.
    /// - Parameter pcm: Raw Float32 interleaved PCM samples (exactly frameDuration.sampleCount * channels samples)
    /// - Returns: Encoded Opus frame bytes, or nil on error
    func encode(_ pcm: [Float]) -> Data? {
        guard let encoder = encoder else {
            print("[OpusEncoder] encoder not initialized")
            return nil
        }

        let frameSize = Int32(frameDuration.sampleCount)
        let maxOutputBytes = Int32(4000)  // Opus frames are typically < 250 bytes, but we allocate generously
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(maxOutputBytes))
        defer { outputBuffer.deallocate() }

        let encodedBytes = pcm.withUnsafeBytes { pcmPtr -> Int32 in
            guard let baseAddress = pcmPtr.baseAddress else { return -1 }
            let floatPtr = baseAddress.assumingMemoryBound(to: Float.self)
            return opus_encode_float(
                encoder,
                floatPtr,
                frameSize,
                outputBuffer,
                maxOutputBytes
            )
        }

        guard encodedBytes > 0 else {
            print("[OpusEncoder] encode failed: \(encodedBytes)")
            return nil
        }

        return Data(bytes: outputBuffer, count: Int(encodedBytes))
    }

    deinit {
        if let encoder = encoder {
            opus_encoder_destroy(encoder)
        }
    }
}

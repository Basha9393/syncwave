// OpusDecoder.swift
// Decodes Opus frames back to PCM Float32 audio.
//
// Phase 4 of ROADMAP.md.

import Foundation

// MARK: - OpusDecoder

/// Decodes Opus-encoded frames to Float32 PCM samples using libopus.
class OpusDecoder {

    let sampleRate: Int
    let channels: Int
    private var decoder: OpaquePointer?
    private let maxSamplesPerFrame = 5760  // Max Opus frame at 48kHz

    init(sampleRate: Int = 48000, channels: Int = 2) {
        self.sampleRate = sampleRate
        self.channels = channels

        // Create decoder
        var error: Int32 = 0
        let dec = opus_decoder_create(Int32(sampleRate), Int32(channels), &error)

        guard error == OPUS_OK, let dec = dec else {
            print("[OpusDecoder] init failed: error code \(error)")
            return
        }

        self.decoder = dec
        print("[OpusDecoder] initialized. sampleRate=\(sampleRate)Hz channels=\(channels)")
    }

    /// Decode an Opus frame to Float32 PCM samples.
    /// - Parameter opusFrame: Encoded Opus data from the network
    /// - Returns: Interleaved Float32 PCM samples (L, R, L, R...), or nil on error
    func decode(_ opusFrame: Data) -> [Float]? {
        guard let decoder = decoder else {
            print("[OpusDecoder] decoder not initialized")
            return nil
        }

        let outputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: maxSamplesPerFrame * channels)
        defer { outputBuffer.deallocate() }

        let samplesDecoded = opusFrame.withUnsafeBytes { ptr -> Int32 in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            let uint8Ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            return opus_decode_float(
                decoder,
                uint8Ptr,
                Int32(opusFrame.count),
                outputBuffer,
                Int32(maxSamplesPerFrame),
                0  // 0 = no FEC (forward error correction)
            )
        }

        guard samplesDecoded > 0 else {
            print("[OpusDecoder] decode failed: \(samplesDecoded)")
            return nil
        }

        // Convert to Swift array
        let totalSamples = Int(samplesDecoded) * channels
        let result = Array(UnsafeBufferPointer(start: outputBuffer, count: totalSamples))
        return result
    }

    /// Handle a lost packet using Opus PLC (packet loss concealment).
    /// Call this when a packet doesn't arrive in time.
    /// - Returns: Synthesized audio that blends with surrounding audio
    func concealLostPacket(expectedSampleCount: Int) -> [Float]? {
        guard let decoder = decoder else { return nil }

        let outputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: expectedSampleCount * channels)
        defer { outputBuffer.deallocate() }

        // Pass NULL pointer to opus_decode_float to trigger PLC
        let samplesGenerated = opus_decode_float(
            decoder,
            nil,
            0,
            outputBuffer,
            Int32(expectedSampleCount),
            0
        )

        guard samplesGenerated > 0 else { return nil }

        let totalSamples = Int(samplesGenerated) * channels
        return Array(UnsafeBufferPointer(start: outputBuffer, count: totalSamples))
    }

    deinit {
        if let decoder = decoder {
            opus_decoder_destroy(decoder)
        }
    }
}

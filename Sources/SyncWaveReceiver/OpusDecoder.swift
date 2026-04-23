// OpusDecoder.swift
// Decodes Opus frames back to PCM Float32 audio.
//
// STATUS: Skeleton with implementation notes. Phase 4 of ROADMAP.md.
// Mirrors OpusEncoder.swift on the sender side.

import Foundation

// MARK: - OpusDecoder

/// Decodes Opus-encoded frames to Float32 PCM samples using libopus.
class OpusDecoder {

    let sampleRate: Int
    let channels: Int

    // MARK: - Implementation notes
    //
    // With a bridging header that imports <opus/opus.h>:
    //
    //   var error: Int32 = 0
    //   let decoder = opus_decoder_create(Int32(sampleRate), Int32(channels), &error)
    //   guard error == OPUS_OK else { fatalError("Opus decoder init failed: \(error)") }
    //
    // Decoding:
    //   let maxSamplesPerFrame = 5760  // max Opus frame at 48kHz
    //   let outputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: maxSamplesPerFrame * channels)
    //
    //   opusData.withUnsafeBytes { ptr in
    //       let samplesDecoded = opus_decode_float(
    //           decoder,
    //           ptr.bindMemory(to: UInt8.self).baseAddress,
    //           Int32(opusData.count),
    //           outputBuffer,
    //           Int32(maxSamplesPerFrame),
    //           0  // 0 = no FEC (forward error correction)
    //       )
    //       // samplesDecoded is samples per channel
    //       // Total floats = samplesDecoded * channels
    //   }
    //
    // Packet loss handling:
    //   If a packet is dropped, call opus_decode_float with NULL input — Opus will
    //   use its built-in packet loss concealment (PLC) to generate a plausible substitute.
    //   This sounds much better than silence.

    init(sampleRate: Int = 48000, channels: Int = 2) {
        self.sampleRate = sampleRate
        self.channels = channels
        print("[OpusDecoder] init — not yet implemented.")
    }

    /// Decode an Opus frame to Float32 PCM samples.
    /// - Parameter opusFrame: Encoded Opus data from the network
    /// - Returns: Interleaved Float32 PCM samples (L, R, L, R...), or nil on error
    func decode(_ opusFrame: Data) -> [Float]? {
        // TODO: implement per notes above
        return nil
    }

    /// Handle a lost packet using Opus PLC (packet loss concealment).
    /// Call this when a packet doesn't arrive in time.
    /// - Returns: Synthesized audio that blends with surrounding audio
    func concealLostPacket(expectedSampleCount: Int) -> [Float]? {
        // TODO: call opus_decode_float with NULL input
        // Returns zeros for now (silence) — PLC sounds much better
        return [Float](repeating: 0, count: expectedSampleCount * channels)
    }

    deinit {
        // TODO: opus_decoder_destroy(decoder)
    }
}

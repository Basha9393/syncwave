// AudioTap.swift
// Captures system audio output using CoreAudio Process Tap API (macOS 14.2+)
//
// STATUS: Skeleton with implementation notes. Phase 1 of ROADMAP.md.
//
// References:
//   https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps
//   https://github.com/insidegui/AudioCap
//   https://github.com/makeusabrew/audiotee

import Foundation
import AVFoundation
import CoreAudio

// MARK: - AudioTap

/// Taps the system audio mix and delivers PCM buffers to a callback.
///
/// Usage:
///   let tap = AudioTap()
///   tap.onBuffer = { buffer in
///       // buffer is AVAudioPCMBuffer, Float32, 48kHz, stereo
///   }
///   tap.start()
class AudioTap {

    // Called on a real-time audio thread. Keep this fast — no allocations, no locks.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - Implementation notes
    //
    // Step 1: Request permission
    //   Add to Info.plist:
    //     <key>NSAudioCaptureUsageDescription</key>
    //     <string>SyncWave needs to capture system audio to stream it.</string>
    //
    // Step 2: Create CATapDescription
    //   let tapDesc = CATapDescription(stereoMixdownOfProcesses: [])
    //   // Empty process list = tap the entire system output mix
    //   // To tap a specific app only, pass its audio object ID
    //
    // Step 3: Create an aggregate device that includes the tap
    //   The tap can't be used directly as an input — it must be routed through
    //   an aggregate audio device. See AudioCap source for the exact AudioObjectSetPropertyData calls.
    //
    // Step 4: Attach an AVAudioEngine input node to the aggregate device
    //   let engine = AVAudioEngine()
    //   // Set the engine's input device to the aggregate device
    //   let inputNode = engine.inputNode
    //   let format = inputNode.outputFormat(forBus: 0)
    //   inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
    //       self?.onBuffer?(buffer)
    //   }
    //   try engine.start()
    //
    // Note: The aggregate device setup is the fiddly part. The AudioCap repo
    // (github.com/insidegui/AudioCap) has a complete working implementation —
    // use it as a reference for the exact property IDs and setup sequence.

    private var engine: AVAudioEngine?
    private let tapQueue = DispatchQueue(label: "com.syncwave.audio-tap", qos: .userInitiated)
    private let targetSampleRate: Double = 48_000

    func start() {
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Temporary phase-1 implementation:
        // capture from default input device while CoreAudio process-tap integration is pending.
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: targetSampleRate,
                                               channels: inputFormat.channelCount,
                                               interleaved: false) else {
            print("[AudioTap] failed to create target format")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let converted = self.convert(buffer: buffer, to: targetFormat) ?? buffer
            self.tapQueue.async {
                self.onBuffer?(converted)
            }
        }

        do {
            try engine.start()
            self.engine = engine
            print("[AudioTap] started (interim input-device mode, 48kHz)")
        } catch {
            inputNode.removeTap(onBus: 0)
            print("[AudioTap] failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        print("[AudioTap] stopped.")
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var hadInput = false
        let status = converter.convert(to: output, error: nil) { _, outStatus in
            if hadInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            hadInput = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status == .haveData || status == .endOfStream else { return nil }
        return output
    }
}

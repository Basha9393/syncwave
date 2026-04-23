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

    func start() {
        // TODO: implement per notes above
        print("[AudioTap] start() — not yet implemented. See implementation notes in source.")
    }

    func stop() {
        engine?.stop()
        engine = nil
        print("[AudioTap] stopped.")
    }
}

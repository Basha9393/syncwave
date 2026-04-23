// AudioPlayer.swift
// Plays decoded PCM audio on the system output using AVAudioEngine.
// Supports scheduled playback at precise timestamps for sync.
//
// STATUS: Skeleton with implementation notes. Phase 4 (basic) + Phase 5 (sync).

import Foundation
import AVFoundation

// MARK: - AudioPlayer

/// Feeds decoded PCM buffers to AVAudioPlayerNode with precise scheduling.
///
/// Phase 4: call play(buffer:) and audio plays immediately (no sync)
/// Phase 5: call play(buffer:atNTPTime:) and audio plays at the correct absolute time
class AudioPlayer {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat?

    // MARK: - Setup

    func setup(sampleRate: Double = 48000, channels: AVAudioChannelCount = 2) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
        self.audioFormat = format

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        try engine.start()
        playerNode.play()

        print("[AudioPlayer] engine started. format=\(format?.description ?? "nil")")
    }

    // MARK: - Phase 4: Immediate playback (no sync)

    /// Schedule a buffer for immediate playback.
    /// Use this in Phase 4 to verify end-to-end audio before adding sync.
    func play(buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - Phase 5: Synchronized playback

    /// Schedule a buffer to play at a specific NTP time.
    ///
    /// How it works:
    /// 1. The sender embeds an NTP timestamp in each RTP packet
    /// 2. The receiver converts that NTP time to AVAudioTime using the host clock
    /// 3. AVAudioPlayerNode schedules the buffer to start at exactly that host time
    /// 4. All receivers do the same → they all start the same buffer at the same moment
    ///
    /// - Parameters:
    ///   - buffer: Decoded PCM audio
    ///   - ntpTime: The wall-clock time (in seconds since 1970) when this buffer should start playing
    func play(buffer: AVAudioPCMBuffer, atNTPTime ntpTime: TimeInterval) {
        // Convert NTP wall time → AVAudioTime (host time)
        //
        // AVAudioTime uses mach_absolute_time() internally.
        // We need to map "seconds since 1970" to "mach ticks".
        //
        // Steps:
        //   let now_ntp = Date().timeIntervalSince1970
        //   let now_host = mach_absolute_time()
        //   let delta_ntp = ntpTime - now_ntp        // how far in the future is play time?
        //   let delta_host = delta_ntp * machTicksPerSecond
        //   let play_host = now_host + UInt64(delta_host)
        //   let avTime = AVAudioTime(hostTime: play_host)
        //
        // If delta_ntp is negative (packet arrived late), drop the buffer.
        // If delta_ntp > jitter buffer max (e.g. > 100ms), something is wrong — log and drop.

        // TODO Phase 5: implement time conversion
        // For now, fall back to immediate playback
        play(buffer: buffer)
    }

    // MARK: - Teardown

    func stop() {
        playerNode.stop()
        engine.stop()
    }
}

// MARK: - Mach time helpers

/// Convert seconds to mach_absolute_time ticks.
/// Call once at startup and cache the result.
func machTicksPerSecond() -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    // mach_absolute_time is in nanoseconds * (numer/denom)
    // ticks per second = 1e9 * denom / numer
    return 1e9 * Double(info.denom) / Double(info.numer)
}

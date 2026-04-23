# Synchronization

How SyncWave keeps multiple Macs playing the same audio at the same moment.

---

## The Core Problem

Two Macs receiving the same audio stream will play it at slightly different times unless told explicitly when to play each chunk. Even 10ms of offset is audible as a comb-filter effect (phasey sound) when speakers are in the same room.

## The Solution: Scheduled Playback via RTP Timestamps

Every RTP packet carries a **timestamp** — a sample offset from the start of the stream. For example, the first packet has timestamp 0, the second has timestamp 480 (one 10ms frame at 48kHz), the third has timestamp 960, and so on.

To turn a sample offset into an absolute wall-clock play time, the sender also transmits **RTCP Sender Reports** that map RTP timestamps to NTP wall time:

```
RTCP SR: {
  ntp_timestamp: 1700000000.123,   ← wall clock seconds since 1970
  rtp_timestamp: 48000             ← the RTP timestamp at that moment
}
```

From this, any receiver can compute: "RTP timestamp X should play at NTP time Y."

## On the Receiver Side

```
Packet arrives with RTP timestamp T
  │
  ▼
Compute NTP play time:
  play_ntp = sr.ntp + (T - sr.rtp) / sample_rate

  ▼
Convert NTP time to AVAudioTime (host time):
  delta = play_ntp - Date().timeIntervalSince1970
  play_host = mach_absolute_time() + delta * machTicksPerSecond

  ▼
Schedule buffer:
  playerNode.scheduleBuffer(buffer, at: AVAudioTime(hostTime: play_host))
```

All receivers run the same calculation. Since they share the same NTP reference, they all schedule playback at the same host-clock moment.

## Jitter Buffer

Network packets don't arrive perfectly on time. A "jitter buffer" absorbs this variance:

```
Target: play each packet 20ms after its "ideal" arrival time

If packet arrives early → hold it until play time
If packet arrives on time → play it at play time
If packet arrives late (but within 20ms window) → play it, slightly late
If packet is very late (> 20ms) → drop it, use PLC to fill the gap
```

**Target buffer size: 20ms**

This means there's a constant 20ms of intentional delay, but all receivers have the same 20ms delay, so they stay in sync.

## NTP Accuracy

On a home LAN, NTP is typically accurate to 1–5ms. This is sufficient:
- Human hearing detects echo/flange above ~10ms
- With 1–5ms NTP error, worst case is 5ms offset between receivers

For professional use (sub-millisecond sync), use PTP (IEEE 1588) instead. macOS supports PTP via the `Network` framework, but setup is more complex.

## Clock Drift

Over long sessions, clocks can drift apart slightly even with NTP. The RTCP Sender Report approach handles this automatically — the sender keeps transmitting SR packets, and receivers re-anchor their mapping whenever a new SR arrives.

## Debugging Sync

To measure sync quality:
1. Record audio on both Macs simultaneously (using QuickTime or similar)
2. Align the waveforms in a DAW
3. Measure the offset in milliseconds

A good result is <5ms offset. Anything under 10ms is imperceptible in a home listening setup.

If sync is drifting over time:
- Check that RTCP SR packets are being transmitted (every 5 seconds is reasonable)
- Check NTP is running on all Macs: `sntp -d time.apple.com`
- Increase the jitter buffer size if you're getting dropouts before drift

## macOS AVAudioTime and Host Clock

`AVAudioTime` wraps macOS's `mach_absolute_time()` clock. It's the most precise clock available on Apple hardware, updated every ~42 nanoseconds. All audio scheduling in CoreAudio is based on this clock — which means scheduled playback can be very precise, as long as the NTP-to-host-clock mapping is correct.

```swift
// Get current host time
let hostNow = mach_absolute_time()

// Get mach ticks per second (call once, cache this)
var info = mach_timebase_info_data_t()
mach_timebase_info(&info)
let ticksPerSec = 1e9 * Double(info.denom) / Double(info.numer)

// Convert a future NTP time to a host time
let deltaSecs = futureNTPTime - Date().timeIntervalSince1970
let hostPlayTime = hostNow + UInt64(deltaSecs * ticksPerSec)
let avTime = AVAudioTime(hostTime: hostPlayTime)

// Schedule
playerNode.scheduleBuffer(buffer, at: avTime)
```

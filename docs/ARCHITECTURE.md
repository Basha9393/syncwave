# Architecture

A complete technical breakdown of every layer in SyncWave.

---

## 1. Audio Capture — CoreAudio Process Tap

### Why not a virtual audio driver?

Airfoil (and older tools like Soundflower/BlackHole) work by installing a virtual audio device at the kernel level. The user manually routes audio through it. This approach:
- Requires system extensions or kernel extensions
- Needs a restart to install/uninstall
- Can break across macOS updates
- Doesn't survive OS audio device switching

### CoreAudio Tap (macOS 14.2+)

Apple introduced `CATapDescription` and the Process Tap API in macOS 14.2. It lets any app "tap" audio from specific processes or the entire system output — no virtual driver, no kernel extension, just a permission prompt.

```swift
// Conceptual flow
let tap = CATapDescription(stereoMixdownOfProcesses: [])  // empty = system mix
// Attach to an aggregate device
// Receive PCM buffers via callback
```

**Key classes:**
- `CATapDescription` — describes what to tap (which processes, channel layout)
- `AVAudioEngine` with a tap node — receives the PCM buffers
- `NSAudioCaptureUsageDescription` in Info.plist — required permission key

**Reference:** https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps

---

## 2. Encoding — Opus

### Why Opus?

AirPlay uses Apple Lossless (ALAC), which is great for quality but adds encoding latency and requires a large buffer. Opus is designed for real-time transmission:

| Codec | Frame size | Latency | Quality |
|---|---|---|---|
| ALAC (AirPlay) | ~1024 samples | ~23ms + buffer | Lossless |
| Opus (SyncWave) | 480 samples | ~10ms | Transparent at 128kbps |
| Opus (low latency) | 120 samples | ~2.5ms | Good at 96kbps |

### Recommended settings

```
Sample rate:    48000 Hz (Opus native rate)
Channels:       2 (stereo)
Frame size:     480 samples (10ms frames) — good balance
Bitrate:        128 kbps (transparent quality for music)
Application:    OPUS_APPLICATION_AUDIO (not VOIP)
```

For lower latency at cost of some quality, use 240-sample frames (5ms).

### libopus integration

Install via Homebrew: `brew install opus`

Swift doesn't have a native Opus binding — you'll call the C API via a bridging header or wrap it in a Swift Package with a C target.

---

## 3. Transport — RTP over UDP Multicast

### Why not TCP?

TCP guarantees delivery by retransmitting lost packets. For audio, a retransmit arrives too late to be useful — you'd rather have a tiny gap than a 100ms stutter. UDP drops the packet and moves on, which is the right behavior for real-time audio.

### Why multicast instead of multiple unicast streams?

With unicast, the host sends one copy per receiver (3 Macs = 3× bandwidth). With IP multicast, the host sends **one packet** and the network delivers it to all subscribers. This also means all receivers get the exact same packet at the exact same time — critical for sync.

**Multicast address:** `239.0.0.1` (private multicast range, stays on LAN)  
**Port:** `5004` (standard RTP audio port)

### RTP packet structure

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|X|  CC   |M|     PT      |       sequence number         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           timestamp                           |  ← KEY FIELD
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           synchronization source (SSRC) identifier           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         payload (Opus)                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

The **timestamp** field contains the sample offset from stream start. Combined with NTP, every receiver knows exactly when to play each packet.

---

## 4. Clock Synchronization — NTP + RTP Timestamps

This is the core mechanism that makes SyncWave sound like one speaker instead of many slightly-offset ones.

### The problem

Each Mac has its own clock. Even if they're all within a millisecond of "real time," that's enough to cause audible phasing artifacts when the same audio plays on multiple speakers in the same room.

### The solution: shared time reference

1. **NTP** keeps all Macs synchronized to the same wall clock. On a LAN, NTP accuracy is typically 1–5ms. For a home setup this is sufficient — the human ear perceives timing offsets as echo only above ~10ms.

2. **RTCP Sender Reports** (optional but recommended) — the host periodically sends an RTCP packet that maps RTP timestamps to NTP wall time. This allows receivers to re-anchor their playback schedule if NTP drift occurs.

3. **Scheduled playback** — each receiver doesn't play audio as soon as it arrives. Instead, it holds a small jitter buffer and plays each packet at the NTP time corresponding to its RTP timestamp.

### Jitter buffer strategy

```
Packet arrives → calculate NTP play time from RTP timestamp
              → if play time is in future: enqueue at correct position
              → if play time is now: play immediately
              → if play time is past (arrived late): drop packet
```

Buffer size: **20ms** is the target. This absorbs network jitter (packets arriving out-of-order or slightly late) without adding perceptible delay.

### What if NTP isn't precise enough?

For sub-millisecond sync (e.g. if you're monitoring audio professionally), use **PTP (Precision Time Protocol, IEEE 1588)** instead. It achieves <1ms accuracy on a LAN. More complex to implement but the protocol is well-documented.

---

## 5. Playback — AVAudioEngine

On the receiver side, `AVAudioEngine` is the right tool:
- Handles CoreAudio output device management
- Supports scheduled audio playback via `AVAudioPlayerNode`
- Works well with real-time buffer feeding

```swift
// Conceptual flow
let engine = AVAudioEngine()
let playerNode = AVAudioPlayerNode()
engine.attach(playerNode)
engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)
try engine.start()

// When a decoded Opus frame arrives:
playerNode.scheduleBuffer(pcmBuffer, at: playTime)  // playTime from RTP timestamp
```

---

## 6. Network Discovery (future)

Currently the receiver IP address would need to be configured manually. Future improvement: use **Bonjour (mDNS)** for automatic discovery.

The host advertises `_syncwave._udp` on the LAN. Receivers browse for it and join the multicast group automatically. No configuration needed.

---

## Known Limitations

- **Wi-Fi jitter** — Wi-Fi introduces more variable latency than wired Ethernet. The 20ms jitter buffer absorbs most of it, but a very congested network could cause occasional dropouts. Prefer wired connections for best results.
- **macOS 14.2+ required** — the CoreAudio tap API doesn't exist on older versions. Fallback option: use BlackHole as a virtual driver, which works on older macOS but requires manual setup.
- **No Bluetooth support** — by design. Bluetooth adds 50–200ms of its own latency and variable jitter that would undermine the sync. SyncWave is LAN-only.
- **No internet streaming** — UDP multicast doesn't route over the internet. SyncWave is intentionally LAN-only, which simplifies security (no auth needed) and guarantees low latency.

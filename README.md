# SyncWave 🎵

> Low-latency, synchronized multi-Mac audio streaming — a personal Airfoil replacement without the lag.

## The Problem with Airfoil

Airfoil is great software, but it has a fundamental latency issue: it uses AirPlay under the hood, which mandates a ~2-second audio buffer. This is hardwired — Rogue Amoeba confirmed there's no way to remove it. The result is noticeable delay and sync drift across multiple devices.

SyncWave fixes this by bypassing AirPlay entirely and using a proper real-time audio stack.

## How SyncWave Works

```
Host Mac                         LAN                    Receiver Macs
─────────────────────────────────────────────────────────────────────
CoreAudio Tap                                           RTP Listener
  │ (system audio)                                         │
  ▼                                                        ▼
Opus Encoder  ──► RTP/UDP Multicast ──────────────►  Jitter Buffer (~20ms)
  │            (239.0.0.1:5004)                           │
  └─ NTP timestamp embedded per packet                     ▼
                                                     Sync Scheduler
                                                     (play at exact RTP time)
                                                          │
                                                          ▼
                                                     CoreAudio Output
                                                     (system speakers)
```

**Key design decisions:**
- **CoreAudio Process Tap** (macOS 14.2+) — captures system audio natively, no virtual drivers needed
- **Opus codec** — real-time audio compression, configurable down to 2.5ms frame size
- **RTP over UDP multicast** — sends once, all receivers get the same packet simultaneously
- **NTP-anchored timestamps** — every packet carries an absolute play-time; receivers schedule playback to the millisecond
- **~20ms jitter buffer** — absorbs network variance without the 2-second AirPlay buffer

## Latency Comparison

| | Airfoil | SyncWave (target) |
|---|---|---|
| Latency | ~2,000ms (fixed) | ~20–80ms |
| Sync method | Match-to-slowest-device | RTP timestamp per packet |
| Transport | AirPlay | UDP multicast (LAN) |
| Audio capture | Virtual audio driver | CoreAudio tap (native) |
| macOS requirement | 10.14+ | 14.2+ |

## Requirements

- macOS 14.2 or later on **all** Macs (required for CoreAudio tap API)
- All Macs on the **same LAN** (Wi-Fi or wired — wired preferred for lowest jitter)
- Xcode 15+
- `libopus` (via Homebrew: `brew install opus`)

## Quick Start (Current Networking Smoke Test)

This project currently includes a working RTP multicast transport slice with synthetic payloads. It validates sender/receiver networking before audio capture + Opus are wired end-to-end.

1. Build both binaries:

```bash
cd /Users/sadiqbasha/Documents/syncwave
mkdir -p build

swiftc \
  Sources/SyncWaveSender/main.swift \
  Sources/SyncWaveSender/RTPSender.swift \
  Sources/SyncWaveSender/AudioTap.swift \
  Sources/SyncWaveSender/OpusEncoder.swift \
  -o build/syncwave-sender

swiftc \
  Sources/SyncWaveReceiver/main.swift \
  Sources/SyncWaveReceiver/RTPReceiver.swift \
  Sources/SyncWaveReceiver/AudioPlayer.swift \
  Sources/SyncWaveReceiver/OpusDecoder.swift \
  -o build/syncwave-receiver
```

2. Run receiver (terminal 1):

```bash
cd /Users/sadiqbasha/Documents/syncwave
./build/syncwave-receiver
```

3. Run sender (terminal 2):

```bash
cd /Users/sadiqbasha/Documents/syncwave
./build/syncwave-sender
```

Sender source options:
- `--source tone` (default, deterministic test tone)
- `--source tap` (interim real capture path via default input device)

Expected result:
- Sender logs increasing packet counts.
- Receiver logs packet count, instantaneous packets/sec (near ~100/s), sequence numbers, and payload size.

### Optional: Unicast A/B Test

If your Wi-Fi handles multicast poorly, run a direct unicast test:

- Receiver: `./build/syncwave-receiver --transport unicast --host 0.0.0.0 --port 5004`
- Sender: `./build/syncwave-sender --transport unicast --host <receiver-ip> --port 5004`

The sender and receiver also accept multicast overrides:

- `--transport multicast --host 239.0.0.1 --port 5004`

## Project Structure

```
SyncWave/
├── README.md
├── docs/
│   ├── ARCHITECTURE.md       ← Deep dive into every technical decision
│   ├── AUDIO_CAPTURE.md      ← CoreAudio tap setup guide
│   ├── NETWORKING.md         ← RTP/UDP/multicast details
│   ├── SYNC.md               ← Clock sync and jitter buffer strategy
│   └── ROADMAP.md            ← Build order and milestones
├── Sources/
│   ├── SyncWaveSender/       ← Host Mac app (captures + streams)
│   │   ├── main.swift        ← Entry point / skeleton
│   │   ├── AudioTap.swift    ← CoreAudio tap implementation
│   │   ├── OpusEncoder.swift ← Opus encoding wrapper
│   │   └── RTPSender.swift   ← UDP multicast sender
│   └── SyncWaveReceiver/     ← Receiver Mac app (listens + plays)
│       ├── main.swift        ← Entry point / skeleton
│       ├── RTPReceiver.swift ← UDP listener + jitter buffer
│       ├── OpusDecoder.swift ← Opus decoding wrapper
│       └── AudioPlayer.swift ← AVAudioEngine scheduled playback
└── scripts/
    └── setup.sh              ← Install dependencies
```

## Build Order (when you're ready)

1. **Phase 1 — Audio capture:** Get CoreAudio tap working, print PCM data to console
2. **Phase 2 — Encoding:** Pipe PCM into Opus encoder, verify output
3. **Phase 3 — Sending:** Wrap in RTP, send over UDP multicast
4. **Phase 4 — Receiving:** Listen for packets, decode Opus, play via AVAudioEngine
5. **Phase 5 — Sync:** Add NTP timestamps, implement scheduled playback
6. **Phase 6 — Polish:** SwiftUI menubar UI, auto-discovery of receivers

See `docs/ROADMAP.md` for detailed milestones.

## Status

🗂️ **Blueprint stage** — architecture documented, skeletons written, not yet implemented.

---

*Personal project. Not intended for commercial use.*

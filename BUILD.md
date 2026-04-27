# Building SyncWave

Complete guide to building and running SyncWave sender and receiver.

## Prerequisites

### 1. Install libopus via Homebrew

```bash
brew install opus
```

Verify installation:
```bash
brew list opus
```

This installs opus headers to `/opt/homebrew/include/opus/` and library to `/opt/homebrew/lib/libopus.dylib`.

## Building

### Option A: Swift Package Manager (Recommended)

```bash
cd /Users/sadiqbasha/Documents/syncwave

# Build both sender and receiver
swift build

# Build release binary (optimized)
swift build -c release
```

Binaries will be at:
- `.build/debug/syncwave-sender`
- `.build/debug/syncwave-receiver`

Or for release:
- `.build/release/syncwave-sender`
- `.build/release/syncwave-receiver`

### Option B: Xcode

If you want to use Xcode's UI:

```bash
# Generate Xcode project
swift package generate-xcodeproj

# Or just open it
xed .
```

Then build with ⌘B in Xcode.

## Running

### Terminal 1: Start the Receiver

```bash
.build/debug/syncwave-receiver
```

Or with options:
```bash
.build/debug/syncwave-receiver --transport multicast --host 239.0.0.1 --port 5004
```

Expected output:
```
SyncWave Receiver starting...
Transport: multicast
Listening target: 239.0.0.1:5004
Jitter buffer: 20ms
[RTPReceiver] listening mode=multicast on 239.0.0.1:5004
[AudioPlayer] engine started. format=AVAudioFormat(...)
```

### Terminal 2: Start the Sender (Tone Mode)

```bash
.build/debug/syncwave-sender --source tone
```

Or unicast to a specific receiver:
```bash
.build/debug/syncwave-sender --transport unicast --host 127.0.0.1 --port 5004 --source tone
```

Expected output:
```
SyncWave Sender starting...
Transport: multicast
Target: 239.0.0.1:5004
Source: tone
[RTPSender] ready. mode=multicast target=239.0.0.1:5004 ssrc=1234567890
[OpusEncoder] initialized. sampleRate=48000Hz channels=1 bitrate=128000bps
[Sender] sent 100 Opus RTP packets
[Sender] sent 200 Opus RTP packets
...
```

The receiver should play a steady 440Hz tone for ~10 seconds.

### Unicast Mode (Single Mac)

To test on one machine:

**Terminal 1:**
```bash
.build/debug/syncwave-receiver --transport unicast --host 0.0.0.0 --port 5004
```

**Terminal 2:**
```bash
.build/debug/syncwave-sender --transport unicast --host 127.0.0.1 --port 5004 --source tone
```

## Testing System Audio Capture

Once the tone test works, you can test capturing system audio:

```bash
.build/debug/syncwave-sender --source tap
```

**Note:** The current AudioTap implementation captures from the default input device (microphone). Full system audio capture (Phase 1) requires additional CoreAudio Process Tap setup — see ARCHITECTURE.md for details.

## Troubleshooting

### "libopus not found" error

```
ld: library not found for -lopus
```

**Solution:** Ensure libopus is installed:
```bash
brew install opus
brew list opus   # verify installation
```

If using M1/M2 Mac, check the lib path:
```bash
ls -la /opt/homebrew/lib/libopus*
```

### "Cannot open audio device" error

**Solution:** Check system permissions:
- The app may need microphone permission (System Preferences → Security & Privacy)
- Or try running with `sudo` (not ideal, but diagnostic)

### No audio output on receiver

1. Check system volume is not muted
2. Try with `--transport unicast --host 127.0.0.1` first (removes network variables)
3. Check that sender is outputting packets:
   - Should see "[Sender] sent X RTP packets" every 10 lines
   - Receiver should show "[Receiver] packets=X rate=100/s" every 100 packets
4. Monitor network with Wireshark:
   ```bash
   # Show RTP traffic on multicast group
   tcpdump -i en0 -n "udp port 5004"
   ```

## Next Steps

### Phase 2 (Done): Opus Encoding/Decoding
- ✅ `OpusEncoder.swift` — converts Float32 PCM to Opus frames
- ✅ `OpusDecoder.swift` — converts Opus frames back to Float32 PCM

### Phase 3 (Done): RTP Transport
- ✅ `RTPSender.swift` — sends RTP packets over UDP multicast
- ✅ `RTPReceiver.swift` — receives RTP packets

### Phase 4 (Done): Playback
- ✅ `AudioPlayer.swift` — plays decoded audio on system output

### Phase 5 (In Progress): Synchronization
- [ ] NTP timestamp embedding in RTP packets
- [ ] Jitter buffer scheduled playback
- [ ] Clock drift detection

### Phase 6 (Future): Menubar UI
- [ ] SwiftUI sender app (start/stop, show receivers)
- [ ] SwiftUI receiver app (connection status, volume)
- [ ] Bonjour discovery (auto-join without manual IP)
- [ ] Settings persistence

## Performance Notes

- **Latency:** ~10ms encoding + ~20ms jitter buffer + ~10ms network = ~40ms typical
- **CPU:** Opus encoding at 48kHz stereo uses ~2-3% CPU per core
- **Bandwidth:** 128kbps Opus = ~16 KB/s per sender
- **Network:** Multicast limits: ~10-20 receivers per LAN switch before congestion

## References

- [libopus documentation](https://opus-codec.org/docs/)
- [RTP RFC 3550](https://www.rfc-editor.org/rfc/rfc3550)
- [AVAudioEngine docs](https://developer.apple.com/documentation/avfoundation/avaudioengine)
- [CoreAudio Process Tap](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)

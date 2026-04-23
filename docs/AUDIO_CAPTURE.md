# Audio Capture

How SyncWave captures system audio on the host Mac using the CoreAudio tap API.

---

## The Old Way (virtual audio drivers)

Before macOS 14.2, capturing system audio required:
1. Installing a virtual audio device (SoundFlower, BlackHole) at the kernel level
2. Manually routing audio through it in System Preferences
3. Dealing with driver breakage after OS updates

Airfoil uses this approach via its own custom driver.

## The New Way (CoreAudio Process Tap)

Since macOS 14.2, Apple provides a native API:
- `CATapDescription` — describes which audio to capture
- No kernel extension required
- Survives OS updates
- Requires user permission (standard privacy prompt)
- Can capture all system audio, or just specific apps

## Required Permission

Add to Info.plist:
```xml
<key>NSAudioCaptureUsageDescription</key>
<string>SyncWave captures your system audio to stream it to other Macs on your network.</string>
```

Without this, the API returns a permission error.

## Setup Overview

The tap can't be used directly as an audio input. It must be routed through an **aggregate audio device**:

```
System audio output
       │
   CATap (tap descriptor)
       │
   Aggregate device (virtual device that combines tap + real output)
       │
   AVAudioEngine input node
       │
   Your PCM buffer callback
```

The aggregate device is the annoying part — it requires low-level `AudioObjectSetPropertyData` calls. The best reference is:
- https://github.com/insidegui/AudioCap (complete working Swift implementation)

## Key API Classes

### CATapDescription
Specifies what to tap:
```swift
// Tap the entire system output mix
let tap = CATapDescription(stereoMixdownOfProcesses: [])

// Tap only specific apps (pass their audio object IDs)
let tap = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
```

### Aggregate Device
Created via `AudioObjectSetPropertyData` with `kAudioPlugInCreateAggregateDevice`. The aggregate device bundles the tap's output as an input source.

### AVAudioEngine Tap
Once the aggregate device is set up, attach an `AVAudioEngine` to it and install a tap on the input node:
```swift
let engine = AVAudioEngine()
// ... set engine's input device to the aggregate device ...
let inputNode = engine.inputNode
let format = inputNode.outputFormat(forBus: 0)

inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
    // buffer is AVAudioPCMBuffer, Float32, 48kHz stereo
    // This callback runs on a real-time audio thread
    // Do NOT allocate memory or take locks here
}

try engine.start()
```

## Audio Format

The tap delivers audio in the system's native format, typically:
- **Sample rate:** 48,000 Hz
- **Format:** Float32, non-interleaved (separate buffers per channel)
- **Channels:** 2 (stereo)

Before passing to Opus, convert to **interleaved Float32** (L, R, L, R...).

## Reference Implementations

These open-source projects implement CoreAudio tap correctly — study them before implementing:

- **AudioCap** — https://github.com/insidegui/AudioCap
  SwiftUI app showing the complete tap + aggregate device setup.
  
- **AudioTee** — https://github.com/makeusabrew/audiotee
  Command-line tool that streams system audio to stdout. Very clean implementation.

Both projects use the same underlying approach. AudioCap is more complete;
AudioTee is simpler and easier to understand.

## Common Issues

**"Permission denied" when creating tap**
→ Check Info.plist has NSAudioCaptureUsageDescription. Check the app is signed (even ad-hoc signing works for local use).

**Tap returns silence**
→ Make sure audio is actually playing on the system before testing.

**Format mismatch**
→ The aggregate device's input format must match what AVAudioEngine expects. Use the format reported by `inputNode.outputFormat(forBus: 0)` — don't hardcode 48kHz.

**Works in Xcode, crashes when run standalone**
→ Entitlements. Add `com.apple.security.device.audio-input` to your .entitlements file.

# Roadmap

Build order designed to give you working audio at each phase, adding sync and polish incrementally.

---

## Phase 1 — Audio Capture ✅ (start here)

**Goal:** Tap system audio and print PCM data to the terminal. No networking yet.

**Tasks:**
- [ ] Set up Xcode project for SyncWaveSender (macOS command-line tool)
- [ ] Add `NSAudioCaptureUsageDescription` to Info.plist
- [ ] Implement `AudioTap.swift` using `CATapDescription`
- [ ] Verify: run the app, play music, see PCM buffer values in console

**Success criteria:** Console shows non-zero PCM buffer data while audio plays.

**Estimated effort:** 1 session (2–4 hours)

**References:**
- https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps
- https://github.com/insidegui/AudioCap (open-source reference implementation)

---

## Phase 2 — Opus Encoding

**Goal:** Take PCM buffers from Phase 1 and encode them to Opus frames.

**Tasks:**
- [ ] Install libopus: `brew install opus`
- [ ] Create Swift bridging header or C target for libopus
- [ ] Implement `OpusEncoder.swift` — init encoder, feed PCM, get encoded bytes
- [ ] Verify: encoded bytes are non-empty and smaller than raw PCM

**Success criteria:** Encoding 10ms of PCM produces ~160 bytes of Opus data.

**Estimated effort:** 1 session

---

## Phase 3 — UDP Multicast Sending

**Goal:** Send Opus frames over the network as RTP packets.

**Tasks:**
- [ ] Implement `RTPSender.swift` — open UDP socket, join multicast group
- [ ] Build minimal RTP packet structure (header + Opus payload)
- [ ] Add sequence number and basic timestamp (wall clock for now)
- [ ] Verify: run Wireshark on another Mac, see UDP packets arriving on 239.0.0.1:5004

**Success criteria:** Packets visible in Wireshark on a second Mac.

**Estimated effort:** 1 session

---

## Phase 4 — Receiving and Playback

**Goal:** Receive packets on a second Mac and play audio (sync doesn't matter yet — just make it play).

**Tasks:**
- [ ] Set up Xcode project for SyncWaveReceiver (separate macOS command-line tool)
- [ ] Implement `RTPReceiver.swift` — bind UDP socket, join multicast group, receive packets
- [ ] Implement `OpusDecoder.swift` — decode Opus frames back to PCM
- [ ] Implement `AudioPlayer.swift` — feed PCM to `AVAudioPlayerNode` in real-time
- [ ] Verify: audio plays on the receiver Mac (even if slightly out of sync with host)

**Success criteria:** Music plays on both Macs simultaneously (rough sync acceptable).

**Estimated effort:** 1–2 sessions

---

## Phase 5 — Clock Sync (the hard part)

**Goal:** Both Macs play in perfect sync — no echo, no drift.

**Tasks:**
- [ ] Read system NTP time in sender: `clock_gettime(CLOCK_REALTIME)`
- [ ] Embed absolute NTP timestamp in each RTP packet (use RTCP SR format)
- [ ] In receiver: calculate scheduled play time from RTP timestamp
- [ ] Use `AVAudioTime` with host time for precise scheduling
- [ ] Implement jitter buffer: hold 20ms of packets, play at scheduled time
- [ ] Test: play audio, walk between the two Macs — no audible echo

**Success criteria:** Standing between two receiving Macs, audio sounds like one speaker.

**Estimated effort:** 2–3 sessions (most debugging will happen here)

**Tips:**
- Start with a 50ms jitter buffer, tune down to 20ms once stable
- Log the delta between scheduled and actual play time to diagnose drift
- If sync drifts over time, add RTCP Sender Reports for clock re-anchoring

---

## Phase 6 — Menubar UI

**Goal:** Replace command-line tools with a proper menubar app.

**Tasks:**
- [ ] SwiftUI menubar app for Sender (start/stop, show connected receivers)
- [ ] SwiftUI menubar app for Receiver (show connection status, volume)
- [ ] Bonjour advertisement from Sender
- [ ] Bonjour discovery in Receiver (auto-join without manual IP config)
- [ ] Persist settings (multicast address, port, buffer size)

**Estimated effort:** 2–3 sessions

---

## Phase 7 — Polish (optional)

- [ ] Per-receiver volume control
- [ ] Audio source selector (all system audio vs specific app)
- [ ] Connection quality indicator (packet loss %, current jitter)
- [ ] Auto-reconnect if network drops
- [ ] Graceful handling of macOS audio device changes (headphones plugged in, etc.)

---

## Not planned

- Bluetooth support (adds uncontrollable latency)
- Internet streaming (multicast is LAN-only by design)
- iOS/tvOS receivers (possible but scope creep)
- Commercial distribution

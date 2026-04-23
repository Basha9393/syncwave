# SyncWave Build TODO

This is the working execution list for turning the blueprint into a running system.

## Current Sprint (Now)

- [x] Define an actionable implementation backlog.
- [x] Implement multicast RTP send path with real socket code.
- [x] Implement multicast RTP receive path with real socket code.
- [x] Wire sender/receiver entry points for packet-flow verification.
- [ ] Add basic local run instructions for validating Phase 3/4 networking.

## Phase 1: Audio Capture

- [ ] Build CoreAudio tap implementation in `Sources/SyncWaveSender/AudioTap.swift`.
- [ ] Add required capture usage description to app configuration.
- [ ] Verify non-zero PCM buffers while system audio plays.

## Phase 2: Opus Encode/Decode

- [ ] Add `libopus` integration strategy (bridging header or C wrapper).
- [ ] Implement `Sources/SyncWaveSender/OpusEncoder.swift`.
- [ ] Implement `Sources/SyncWaveReceiver/OpusDecoder.swift`.
- [ ] Validate encode/decode quality and frame sizing.

## Phase 3: RTP Multicast Transport

- [ ] Sender socket setup, TTL, packet transmit loop.
- [ ] Receiver socket bind, multicast join, background receive loop.
- [ ] Parse RTP headers and surface payload callbacks.
- [ ] Smoke test on one Mac, then two Macs on LAN.

## Phase 4: Playback Pipeline

- [ ] Convert decoded PCM to `AVAudioPCMBuffer`.
- [ ] Feed buffers into `AudioPlayer`.
- [ ] Confirm audible playback on receiver.

## Phase 5: Synchronization

- [ ] Add absolute sender timestamps.
- [ ] Implement jitter buffer with reordering and late-drop policy.
- [ ] Schedule playback against host time for low drift.

## Phase 6+: Productization

- [ ] Menubar UX for sender/receiver lifecycle.
- [ ] Discovery (Bonjour), status, and settings persistence.
- [ ] Reliability metrics, logging, and reconnection behavior.

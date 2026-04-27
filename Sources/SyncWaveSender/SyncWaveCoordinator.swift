// SyncWaveCoordinator.swift
// Orchestrates sender and receiver logic
// Manages networking, audio streaming, and device discovery

import Foundation
import Combine

// MARK: - SyncWave Coordinator

@MainActor
class SyncWaveCoordinator: NSObject, ObservableObject {
    enum Role {
        case sender
        case receiver
    }

    // MARK: - Published Properties

    @Published var selectedRole: Role = .sender {
        didSet {
            roleChanged()
        }
    }

    @Published var isActive = false
    @Published var statusText = "Ready"

    // Sender properties
    @Published var connectedReceivers: [BonjourService.Service] = []
    @Published var packetsSent: UInt64 = 0

    // Receiver properties
    @Published var availableSenders: [BonjourService.Service] = []
    @Published var packetsReceived: UInt64 = 0

    // MARK: - Private Properties

    private var bonjour = BonjourService()
    private var audioTap: AudioTap?
    private var rtpSender: RTPSender?
    private var rtpReceiver: RTPReceiver?
    private var opusEncoder: OpusEncoder?
    private var opusDecoder: OpusDecoder?
    private var audioPlayer: AudioPlayer?

    private var senderTimer: Timer?
    private var statsTimer: Timer?

    private var pendingMonoSamples: [Float] = []
    private let frameSamples = 480
    private let sampleRate: Double = 48_000

    // MARK: - Initialization

    override init() {
        super.init()
        setupBonjour()
    }

    // MARK: - Bonjour Setup

    private func setupBonjour() {
        bonjour.onServiceFound = { [weak self] service in
            Task { @MainActor in
                if service.type == .sender {
                    self?.availableSenders.append(service)
                }
            }
        }

        bonjour.onServiceLost = { [weak self] service in
            Task { @MainActor in
                self?.availableSenders.removeAll { $0.name == service.name }
                self?.connectedReceivers.removeAll { $0.name == service.name }
            }
        }

        bonjour.onError = { [weak self] error in
            Task { @MainActor in
                self?.statusText = "Discovery error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Role Management

    private func roleChanged() {
        stopSender()
        stopReceiver()

        if selectedRole == .sender {
            statusText = "Sender mode - click Start Broadcasting"
            bonjour.stopBrowsing()
            bonjour.startAdvertisingAsService(
                name: NSHost.current().localizedName ?? "SyncWave Sender",
                port: 5004,
                type: .sender
            )
        } else {
            statusText = "Receiver mode - discovering senders..."
            bonjour.stopAdvertising()
            bonjour.startBrowsingForServices(type: .sender)
        }
    }

    // MARK: - Sender Control

    func startSender() {
        print("[Coordinator] Starting sender...")

        // Setup audio tap
        audioTap = AudioTap()
        opusEncoder = OpusEncoder(sampleRate: 48000, channels: 1, frameDuration: .ms10, bitrate: 128_000)
        rtpSender = RTPSender(targetHost: "239.0.0.1", port: 5004, samplesPerFrame: 480, transportMode: .multicast)

        // Setup timer to generate tone for testing (until AudioTap is fully working)
        var phase: Double = 0
        let toneFrequencyHz: Double = 440.0
        let amplitude: Double = 0.20
        let phaseStep = (2.0 * Double.pi * toneFrequencyHz) / sampleRate

        senderTimer = Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { [weak self] _ in
            guard let self else { return }

            var pcmSamples = [Float](repeating: 0, count: self.frameSamples)
            for i in 0..<self.frameSamples {
                let sampleValue = sin(phase) * amplitude
                pcmSamples[i] = Float(max(-1.0, min(1.0, sampleValue)))
                phase += phaseStep
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
            }

            if let opusFrame = self.opusEncoder?.encode(pcmSamples) {
                self.rtpSender?.send(opusFrame)
                self.packetsSent += 1
            }
        }

        isActive = true
        statusText = "Broadcasting system audio..."

        // Start stats timer
        statsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.statusText = "Broadcasting... (\(self.packetsSent) packets)"
        }
    }

    func stopSender() {
        senderTimer?.invalidate()
        senderTimer = nil
        statsTimer?.invalidate()
        statsTimer = nil

        audioTap?.stop()
        audioTap = nil
        rtpSender = nil
        opusEncoder = nil

        isActive = false
        statusText = "Stopped"
        packetsSent = 0
    }

    // MARK: - Receiver Control

    func connectToSender(_ sender: BonjourService.Service) {
        print("[Coordinator] Connecting to sender: \(sender.name) at \(sender.host):\(sender.port)")

        // Setup receiver
        opusDecoder = OpusDecoder(sampleRate: 48000, channels: 1)
        audioPlayer = AudioPlayer()

        do {
            try audioPlayer?.setup(sampleRate: 48000, channels: 2)
        } catch {
            print("[Coordinator] Failed to setup audio player: \(error)")
            statusText = "Audio setup failed"
            return
        }

        rtpReceiver = RTPReceiver(listenAddress: "239.0.0.1", port: 5004, transportMode: .multicast)

        var jitterBuffer: [UInt16: Data] = [:]
        var expectedPlayoutSequence: UInt16?
        var lastGoodPayload: Data?

        rtpReceiver?.onPacket = { [weak self] packet in
            guard let self else { return }

            jitterBuffer[packet.sequenceNumber] = packet.payload

            // Simple jitter buffer playback every 10ms
            DispatchQueue.main.async {
                if expectedPlayoutSequence == nil {
                    guard jitterBuffer.count >= 3 else { return }
                    expectedPlayoutSequence = jitterBuffer.keys.min()
                }

                guard let seq = expectedPlayoutSequence else { return }

                let opusData: Data?
                if let payload = jitterBuffer.removeValue(forKey: seq) {
                    opusData = payload
                    lastGoodPayload = payload
                } else {
                    opusData = lastGoodPayload
                }

                if let opusData = opusData, let decodedFloat32 = self.opusDecoder?.decode(opusData) {
                    if let stereoBuffer = self.makeStereoBufferFromMonoFloat32(decodedFloat32) {
                        self.audioPlayer?.play(buffer: stereoBuffer)
                    }
                } else if let lastGood = lastGoodPayload, let decodedFloat32 = self.opusDecoder?.decode(lastGood) {
                    if let stereoBuffer = self.makeStereoBufferFromMonoFloat32(decodedFloat32) {
                        self.audioPlayer?.play(buffer: stereoBuffer)
                    }
                }

                expectedPlayoutSequence = seq &+ 1

                if jitterBuffer.count > 500, let oldest = jitterBuffer.keys.min() {
                    jitterBuffer.removeValue(forKey: oldest)
                }

                self.packetsReceived += 1
            }
        }

        rtpReceiver?.start()
        isActive = true
        statusText = "Connected to \(sender.name)"

        statsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.statusText = "Connected... (\(self.packetsReceived) packets)"
        }
    }

    func stopReceiver() {
        statsTimer?.invalidate()
        statsTimer = nil

        rtpReceiver?.stop()
        rtpReceiver = nil
        audioPlayer?.stop()
        audioPlayer = nil
        opusDecoder = nil

        isActive = false
        statusText = "Disconnected"
        packetsReceived = 0
    }

    // MARK: - Helper

    private func makeStereoBufferFromMonoFloat32(_ mono: [Float]) -> AVAudioPCMBuffer? {
        let frameCount = mono.count
        guard frameCount > 0 else { return nil }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for i in 0..<frameCount {
            let value = max(-1.0, min(1.0, mono[i]))
            left[i] = value
            right[i] = value
        }
        return buffer
    }

    deinit {
        bonjour.stopAdvertising()
        bonjour.stopBrowsing()
        stopSender()
        stopReceiver()
    }
}

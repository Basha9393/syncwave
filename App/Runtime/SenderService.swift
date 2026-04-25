import Foundation
import AVFoundation

final class SenderService {
    private var sender: RTPSender?
    private var tap: AudioTap?
    private var toneTimer: Timer?
    private var pendingMonoSamples: [Float] = []
    private var sentPacketCount: UInt64 = 0
    private var metricsHandler: ((RuntimeMetrics) -> Void)?

    private let frameSamples = 480
    private let sampleRate: Double = 48_000
    private var phase: Double = 0
    private let toneFrequencyHz: Double = 440.0
    private let amplitude: Double = 0.20

    func start(settings: RuntimeSettings, onMetrics: @escaping (RuntimeMetrics) -> Void) {
        stop()
        metricsHandler = onMetrics
        sender = RTPSender(
            targetHost: settings.host,
            port: settings.port,
            samplesPerFrame: frameSamples,
            transportMode: settings.transport == .multicast ? .multicast : .unicast
        )
        sentPacketCount = 0
        phase = 0

        switch settings.source {
        case .tone:
            startToneMode()
        case .tap:
            startTapMode()
        }
    }

    func stop() {
        toneTimer?.invalidate()
        toneTimer = nil
        tap?.stop()
        tap = nil
        sender = nil
        pendingMonoSamples.removeAll(keepingCapacity: false)
        publishStatus("Sender stopped")
    }

    private func startToneMode() {
        let phaseStep = (2.0 * Double.pi * toneFrequencyHz) / sampleRate
        toneTimer = Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { [weak self] _ in
            guard let self else { return }
            var payload = Data(count: self.frameSamples * MemoryLayout<Int16>.size)
            payload.withUnsafeMutableBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: Int16.self)
                guard let baseAddress = samples.baseAddress else { return }
                for i in 0..<self.frameSamples {
                    let sampleValue = sin(self.phase) * self.amplitude
                    let pcm = Int16(max(-1.0, min(1.0, sampleValue)) * Double(Int16.max))
                    baseAddress[i] = pcm.littleEndian
                    self.phase += phaseStep
                    if self.phase >= 2.0 * Double.pi {
                        self.phase -= 2.0 * Double.pi
                    }
                }
            }
            self.send(payload)
        }
        publishStatus("Sender running (tone)")
    }

    private func startTapMode() {
        let tap = AudioTap()
        tap.onBuffer = { [weak self] buffer in
            self?.consumeTapBuffer(buffer)
        }
        tap.start()
        self.tap = tap
        publishStatus("Sender running (tap)")
    }

    private func consumeTapBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return }

        for frameIndex in 0..<frameCount {
            var mixed: Float = 0
            for channel in 0..<channelCount {
                mixed += channelData[channel][frameIndex]
            }
            pendingMonoSamples.append(mixed / Float(channelCount))
        }

        while pendingMonoSamples.count >= frameSamples {
            var payload = Data(count: frameSamples * MemoryLayout<Int16>.size)
            payload.withUnsafeMutableBytes { rawBuffer in
                let outSamples = rawBuffer.bindMemory(to: Int16.self)
                guard let outBase = outSamples.baseAddress else { return }
                for i in 0..<frameSamples {
                    let clamped = max(-1.0, min(1.0, pendingMonoSamples[i]))
                    outBase[i] = Int16(clamped * Float(Int16.max)).littleEndian
                }
            }
            pendingMonoSamples.removeFirst(frameSamples)
            send(payload)
        }
    }

    private func send(_ payload: Data) {
        sender?.send(payload)
        sentPacketCount += 1
        if sentPacketCount.isMultiple(of: 100) {
            var metrics = RuntimeMetrics()
            metrics.packets = sentPacketCount
            metrics.payloadBytes = payload.count
            metrics.status = "Sender running"
            metricsHandler?(metrics)
        }
    }

    private func publishStatus(_ value: String) {
        var metrics = RuntimeMetrics()
        metrics.status = value
        metricsHandler?(metrics)
    }
}

import Foundation
import AVFoundation

final class ReceiverService {
    private var receiver: RTPReceiver?
    private let player = AudioPlayer()
    private let playbackQueue = DispatchQueue(label: "com.syncwave.app.playback", qos: .userInitiated)
    private var playbackTimer: DispatchSourceTimer?

    private let expectedPacketIntervalSec = 0.010
    private let pcmFrameSamples = 480
    private lazy var pcmBytesPerFrame = pcmFrameSamples * MemoryLayout<Int16>.size
    private lazy var hostTicksPerSecond = machTicksPerSecond()
    private lazy var silencePayload = Data(count: pcmBytesPerFrame)

    private var metricsHandler: ((RuntimeMetrics) -> Void)?

    private var receivedPacketCount: UInt64 = 0
    private var windowPacketCount: UInt64 = 0
    private var windowStart = Date()
    private var lastSequenceNumber: UInt16?
    private var lastReceivedAtTicks: UInt64?
    private var estimatedJitterSec: Double = 0
    private var lostPacketCount: UInt64 = 0
    private var reorderedPacketCount: UInt64 = 0
    private var duplicatePacketCount: UInt64 = 0
    private var streamSSRC: UInt32?
    private var concealmentFrameCount: UInt64 = 0
    private var jitterBuffer: [UInt16: Data] = [:]
    private var expectedPlayoutSequence: UInt16?
    private var lastGoodPayload: Data?
    private let targetPrebufferPackets = 3

    func start(settings: RuntimeSettings, onMetrics: @escaping (RuntimeMetrics) -> Void) {
        stop()
        metricsHandler = onMetrics
        do {
            try player.setup(sampleRate: 48_000, channels: 2)
        } catch {
            publishStatus("Audio setup failed: \(error.localizedDescription)")
            return
        }

        let transport: RTPReceiver.TransportMode = settings.transport == .multicast ? .multicast : .unicast
        receiver = RTPReceiver(listenAddress: settings.host, port: settings.port, transportMode: transport)
        receiver?.onPacket = { [weak self] packet in
            self?.consume(packet: packet)
        }
        receiver?.onError = { [weak self] error in
            self?.publishStatus(error)
        }
        receiver?.start()
        startPlaybackTimer()
        publishStatus("Receiver running")
    }

    func stop() {
        playbackTimer?.cancel()
        playbackTimer = nil
        receiver?.stop()
        receiver = nil
        player.stop()
        resetCounters()
        publishStatus("Receiver stopped")
    }

    private func startPlaybackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: playbackQueue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.playNextFrame()
        }
        playbackTimer = timer
        timer.resume()
    }

    private func playNextFrame() {
        if expectedPlayoutSequence == nil {
            guard jitterBuffer.count >= targetPrebufferPackets else { return }
            expectedPlayoutSequence = jitterBuffer.keys.min()
        }
        guard let sequence = expectedPlayoutSequence else { return }
        let payloadToPlay: Data
        if let payload = jitterBuffer.removeValue(forKey: sequence) {
            payloadToPlay = payload
            lastGoodPayload = payload
        } else {
            concealmentFrameCount += 1
            payloadToPlay = lastGoodPayload ?? silencePayload
        }
        if let buffer = makeStereoBufferFromMonoPCM16(payloadToPlay) {
            player.play(buffer: buffer)
        }
        expectedPlayoutSequence = sequence &+ 1
    }

    private func consume(packet: IncomingRTPPacket) {
        if streamSSRC != packet.ssrc {
            streamSSRC = packet.ssrc
            resetCounters()
            playbackQueue.async { [weak self] in
                self?.jitterBuffer.removeAll(keepingCapacity: true)
                self?.expectedPlayoutSequence = nil
                self?.lastGoodPayload = nil
            }
        }

        receivedPacketCount += 1
        windowPacketCount += 1
        if let lastSeq = lastSequenceNumber {
            let seqDelta = packet.sequenceNumber &- lastSeq
            if seqDelta == 0 {
                duplicatePacketCount += 1
            } else if seqDelta < 0x8000, seqDelta > 1 {
                lostPacketCount += UInt64(seqDelta - 1)
            } else if seqDelta >= 0x8000 {
                reorderedPacketCount += 1
            }
        }
        lastSequenceNumber = packet.sequenceNumber

        if let previousTicks = lastReceivedAtTicks {
            let interArrivalSec = Double(packet.receivedAt &- previousTicks) / hostTicksPerSecond
            let deviation = abs(interArrivalSec - expectedPacketIntervalSec)
            estimatedJitterSec += (deviation - estimatedJitterSec) / 16.0
        }
        lastReceivedAtTicks = packet.receivedAt

        if packet.payload.count == pcmBytesPerFrame {
            playbackQueue.async { [weak self] in
                self?.jitterBuffer[packet.sequenceNumber] = packet.payload
            }
        }

        if receivedPacketCount.isMultiple(of: 100) {
            let now = Date()
            let elapsed = now.timeIntervalSince(windowStart)
            var metrics = RuntimeMetrics()
            metrics.packets = receivedPacketCount
            metrics.rate = elapsed > 0 ? Double(windowPacketCount) / elapsed : 0
            metrics.loss = lostPacketCount
            metrics.lossPercent = receivedPacketCount > 0 ? (Double(lostPacketCount) / Double(receivedPacketCount + lostPacketCount)) * 100.0 : 0
            metrics.reorder = reorderedPacketCount
            metrics.duplicates = duplicatePacketCount
            metrics.concealment = concealmentFrameCount
            metrics.jitterMs = estimatedJitterSec * 1000
            metrics.lastSequence = packet.sequenceNumber
            metrics.payloadBytes = packet.payload.count
            metrics.status = "Receiver running"
            metricsHandler?(metrics)
            windowPacketCount = 0
            windowStart = now
        }
    }

    private func makeStereoBufferFromMonoPCM16(_ payload: Data) -> AVAudioPCMBuffer? {
        let frameCount = payload.count / MemoryLayout<Int16>.size
        guard frameCount > 0 else { return nil }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        payload.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            guard let base = samples.baseAddress else { return }
            for i in 0..<frameCount {
                let value = Float(Int16(littleEndian: base[i])) / Float(Int16.max)
                left[i] = value
                right[i] = value
            }
        }
        return buffer
    }

    private func publishStatus(_ value: String) {
        var metrics = RuntimeMetrics()
        metrics.status = value
        metricsHandler?(metrics)
    }

    private func resetCounters() {
        receivedPacketCount = 0
        windowPacketCount = 0
        windowStart = Date()
        lastSequenceNumber = nil
        lastReceivedAtTicks = nil
        estimatedJitterSec = 0
        lostPacketCount = 0
        reorderedPacketCount = 0
        duplicatePacketCount = 0
        concealmentFrameCount = 0
    }
}

import Foundation

enum AppRole: String, CaseIterable, Identifiable, Codable {
    case sender
    case receiver

    var id: String { rawValue }
}

enum NetworkTransport: String, CaseIterable, Identifiable, Codable {
    case unicast
    case multicast

    var id: String { rawValue }
}

enum SenderSourceMode: String, CaseIterable, Identifiable, Codable {
    case tone
    case tap

    var id: String { rawValue }
}

struct RuntimeSettings: Codable {
    var role: AppRole = .receiver
    var transport: NetworkTransport = .unicast
    var host: String = "0.0.0.0"
    var port: UInt16 = 5004
    var source: SenderSourceMode = .tone
}

struct RuntimeMetrics {
    var packets: UInt64 = 0
    var rate: Double = 0
    var loss: UInt64 = 0
    var lossPercent: Double = 0
    var reorder: UInt64 = 0
    var duplicates: UInt64 = 0
    var concealment: UInt64 = 0
    var jitterMs: Double = 0
    var payloadBytes: Int = 0
    var lastSequence: UInt16 = 0
    var status: String = "Idle"
}

import Foundation

@MainActor
final class MetricsViewModel: ObservableObject {
    @Published var metrics = RuntimeMetrics()

    func update(_ newMetrics: RuntimeMetrics) {
        if newMetrics.packets > 0 { metrics.packets = newMetrics.packets }
        if newMetrics.rate > 0 { metrics.rate = newMetrics.rate }
        if newMetrics.payloadBytes > 0 { metrics.payloadBytes = newMetrics.payloadBytes }
        if newMetrics.lastSequence > 0 { metrics.lastSequence = newMetrics.lastSequence }
        metrics.loss = newMetrics.loss
        metrics.lossPercent = newMetrics.lossPercent
        metrics.reorder = newMetrics.reorder
        metrics.duplicates = newMetrics.duplicates
        metrics.concealment = newMetrics.concealment
        metrics.jitterMs = newMetrics.jitterMs
        metrics.status = newMetrics.status
    }
}

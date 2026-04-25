import Foundation

@MainActor
final class RoleViewModel: ObservableObject {
    @Published var settings: RuntimeSettings
    @Published var isRunning = false
    @Published var discoveredSenders: [DiscoveredSender] = []

    let metrics = MetricsViewModel()

    private let settingsStore: SettingsStore
    private let senderService = SenderService()
    private let receiverService = ReceiverService()
    private let discoveryService = DiscoveryService()

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
    }

    func start() {
        stop()
        isRunning = true
        persist()

        if settings.role == .sender {
            senderService.start(settings: settings) { [weak self] runtimeMetrics in
                Task { @MainActor in self?.metrics.update(runtimeMetrics) }
            }
            discoveryService.startAdvertising(name: Host.current().localizedName ?? "SyncWave Sender", host: settings.host, port: settings.port)
        } else {
            receiverService.start(settings: settings) { [weak self] runtimeMetrics in
                Task { @MainActor in self?.metrics.update(runtimeMetrics) }
            }
            discoveryService.startBrowsing { [weak self] senders in
                Task { @MainActor in self?.discoveredSenders = senders }
            }
        }
    }

    func stop() {
        senderService.stop()
        receiverService.stop()
        discoveryService.stopAdvertising()
        discoveryService.stopBrowsing()
        isRunning = false
    }

    func applyDiscoveredSender(_ sender: DiscoveredSender) {
        settings.transport = .unicast
        settings.host = sender.host
        settings.port = sender.port
        persist()
    }

    func persist() {
        settingsStore.save(settings)
    }
}

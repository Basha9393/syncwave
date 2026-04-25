import Foundation

final class SettingsStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "syncwave-settings.json") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = appSupport.appendingPathComponent("SyncWave", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.url = folder.appendingPathComponent(filename)
    }

    func load() -> RuntimeSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(RuntimeSettings.self, from: data) else {
            return RuntimeSettings()
        }
        return settings
    }

    func save(_ settings: RuntimeSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

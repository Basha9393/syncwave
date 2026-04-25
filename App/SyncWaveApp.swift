import SwiftUI

@main
struct SyncWaveApp: App {
    @StateObject private var roleViewModel = RoleViewModel()

    var body: some Scene {
        WindowGroup("SyncWave") {
            RoleSelectionView(viewModel: roleViewModel)
        }
    }
}

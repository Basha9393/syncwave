// SyncWaveApp.swift
// Main SwiftUI application entry point
// Runs as a menubar app (no dock icon)

import SwiftUI

@main
struct SyncWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("SyncWave", systemImage: "waveform.circle") {
            ContentView()
                .frame(width: 350, height: 600)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon for menubar-only app
        NSApp.setActivationPolicy(.accessory)

        // Request microphone permission (for audio capture)
        requestMicrophonePermission()

        // Request network permission if needed
        print("[App] Initialized as menubar application")
    }

    private func requestMicrophonePermission() {
        // The app will request permission when first accessing audio
        // This is automatic on macOS
        print("[App] Microphone permission will be requested on first audio access")
    }
}

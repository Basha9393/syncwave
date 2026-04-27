// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SyncWave",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "syncwave-sender", targets: ["SyncWaveSender"]),
        .executable(name: "syncwave-receiver", targets: ["SyncWaveReceiver"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SyncWaveSender",
            dependencies: [],
            path: "Sources/SyncWaveSender",
            sources: [
                "SyncWaveApp.swift",
                "ContentView.swift",
                "SyncWaveCoordinator.swift",
                "BonjourService.swift",
                "AudioTap.swift",
                "OpusEncoder.swift",
                "RTPSender.swift"
            ],
            resources: [],
            linkerSettings: [
                .linkedLibrary("opus"),
                .linkedFramework("Foundation"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Network"),
                .unsafeFlags(["-Xcc", "-I/opt/homebrew/include"], .when(platforms: [.macOS])),
                .unsafeFlags(["-L/opt/homebrew/lib"], .when(platforms: [.macOS])),
            ]
        ),
        .executableTarget(
            name: "SyncWaveReceiver",
            dependencies: [],
            path: "Sources/SyncWaveReceiver",
            sources: [
                "main.swift",
                "RTPReceiver.swift",
                "OpusDecoder.swift",
                "AudioPlayer.swift"
            ],
            linkerSettings: [
                .linkedLibrary("opus"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .unsafeFlags(["-Xcc", "-I/opt/homebrew/include"], .when(platforms: [.macOS])),
                .unsafeFlags(["-L/opt/homebrew/lib"], .when(platforms: [.macOS])),
            ]
        ),
    ]
)

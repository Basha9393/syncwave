// ContentView.swift
// Main UI for SyncWave menubar app
// Shows either sender or receiver interface based on user selection

import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var coordinator = SyncWaveCoordinator()

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("SyncWave")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit SyncWave")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Role Selector
            Picker("Mode", selection: $coordinator.selectedRole) {
                Text("Sender").tag(SyncWaveCoordinator.Role.sender)
                Text("Receiver").tag(SyncWaveCoordinator.Role.receiver)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            // Mode-specific content
            if coordinator.selectedRole == .sender {
                SenderView(coordinator: coordinator)
            } else {
                ReceiverView(coordinator: coordinator)
            }

            Spacer()

            // Status footer
            HStack {
                Circle()
                    .fill(coordinator.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(coordinator.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Sender View

struct SenderView: View {
    @ObservedObject var coordinator: SyncWaveCoordinator
    @State private var isStreaming = false

    var body: some View {
        VStack(spacing: 12) {
            // Streaming status
            if isStreaming {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .symbolEffect(.pulse)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Broadcasting")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("System audio is streaming")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Stop") {
                        isStreaming = false
                        coordinator.stopSender()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            } else {
                VStack(spacing: 8) {
                    Button(action: { startStreaming() }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Start Broadcasting")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Broadcasts your system audio (Spotify, YouTube, etc.)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }

            Divider()
                .padding(.horizontal, 0)

            // Connected Receivers
            VStack(alignment: .leading, spacing: 8) {
                Text("Connected Receivers")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)

                if coordinator.connectedReceivers.isEmpty {
                    Text("No receivers connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(coordinator.connectedReceivers, id: \.name) { receiver in
                                HStack {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(receiver.name)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text(receiver.host)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "volume.2.fill")
                                                .font(.caption2)
                                            Text("100%")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            Divider()
                .padding(.horizontal, 0)

            // Statistics
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Packets Sent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(coordinator.packetsSent)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Bitrate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("128 kbps")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Latency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("~50ms")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
    }

    private func startStreaming() {
        coordinator.startSender()
        isStreaming = true
    }
}

// MARK: - Receiver View

struct ReceiverView: View {
    @ObservedObject var coordinator: SyncWaveCoordinator
    @State private var isConnected = false

    var body: some View {
        VStack(spacing: 12) {
            // Connected status
            if isConnected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Receiving audio from sender")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Disconnect") {
                        isConnected = false
                        coordinator.stopReceiver()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            // Available Senders
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Senders")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)

                if coordinator.availableSenders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Looking for senders...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(coordinator.availableSenders, id: \.name) { sender in
                                Button(action: { connectToSender(sender) }) {
                                    HStack {
                                        Image(systemName: "macbook.and.iphone")
                                            .foregroundColor(.blue)
                                            .frame(width: 16)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sender.name)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            Text(sender.host)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            Divider()
                .padding(.horizontal, 0)

            // Volume Control
            if isConnected {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("100%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: .constant(1.0), in: 0...1)
                        .disabled(true)
                }
                .padding(.horizontal, 12)
            }

            Spacer()
        }
    }

    private func connectToSender(_ sender: BonjourService.Service) {
        coordinator.connectToSender(sender)
        isConnected = true
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 350, height: 600)
}

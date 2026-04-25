import SwiftUI

struct RoleSelectionView: View {
    @ObservedObject var viewModel: RoleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Role", selection: $viewModel.settings.role) {
                Text("Sender").tag(AppRole.sender)
                Text("Receiver").tag(AppRole.receiver)
            }
            .pickerStyle(.segmented)

            Picker("Transport", selection: $viewModel.settings.transport) {
                Text("Unicast").tag(NetworkTransport.unicast)
                Text("Multicast").tag(NetworkTransport.multicast)
            }

            HStack {
                Text("Host")
                TextField("Host", text: $viewModel.settings.host)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Port")
                TextField("Port", value: $viewModel.settings.port, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
            }

            if viewModel.settings.role == .sender {
                Picker("Source", selection: $viewModel.settings.source) {
                    Text("Tone").tag(SenderSourceMode.tone)
                    Text("Tap").tag(SenderSourceMode.tap)
                }
            }

            HStack {
                Button(viewModel.isRunning ? "Stop" : "Start") {
                    if viewModel.isRunning { viewModel.stop() } else { viewModel.start() }
                }
                Button("Save") { viewModel.persist() }
            }

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("State: \(viewModel.metrics.metrics.status)")
                    Text("Packets: \(viewModel.metrics.metrics.packets)")
                    Text(String(format: "Rate: %.1f/s", viewModel.metrics.metrics.rate))
                    Text(String(format: "Loss: %llu (%.2f%%)", viewModel.metrics.metrics.loss, viewModel.metrics.metrics.lossPercent))
                    Text("Reorder: \(viewModel.metrics.metrics.reorder), Dup: \(viewModel.metrics.metrics.duplicates), Conceal: \(viewModel.metrics.metrics.concealment)")
                    Text(String(format: "Jitter: %.2fms", viewModel.metrics.metrics.jitterMs))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.settings.role == .receiver {
                GroupBox("Discovered Senders") {
                    if viewModel.discoveredSenders.isEmpty {
                        Text("No senders discovered yet.")
                    } else {
                        List(viewModel.discoveredSenders) { sender in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(sender.name)
                                    Text("\(sender.host):\(sender.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use") { viewModel.applyDiscoveredSender(sender) }
                            }
                        }
                        .frame(height: 140)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 540)
    }
}

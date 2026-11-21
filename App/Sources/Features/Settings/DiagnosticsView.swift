import SwiftUI

/// Shows exactly what the anonymous error reports contain (ADR-0020), and lets a tester send
/// them by hand while no endpoint is configured.
struct DiagnosticsView: View {
    @Environment(Telemetry.self) private var telemetry
    @Environment(SettingsStore.self) private var store

    var body: some View {
        List {
            Section {
                LabeledContent("Reports waiting", value: "\(telemetry.pending.count)")
                LabeledContent("Sending", value: sendingStatus)
                if let lastSent = telemetry.lastSent {
                    LabeledContent("Last sent", value: lastSent.formatted(date: .abbreviated, time: .shortened))
                }
                if let error = telemetry.lastError {
                    LabeledContent("Last problem", value: error)
                }
                if telemetry.endpoint != nil, !telemetry.pending.isEmpty {
                    Button("Send now") { Task { await telemetry.flush() } }
                }
                ShareLink("Share report", item: telemetry.report)
                    .disabled(telemetry.pending.isEmpty)
            } footer: {
                Text("This is everything a report holds. Shared reports go only where you choose to send them.")
            }

            Section("Recent") {
                if telemetry.pending.isEmpty {
                    Text("Nothing to report.").foregroundStyle(.secondary)
                }
                ForEach(telemetry.pending.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.name).font(.headline)
                        Text(event.at.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(event.fields.keys.sorted(), id: \.self) { key in
                            Text("\(key): \(event.fields[key] ?? "")")
                                .font(.caption.monospaced())
                                .lineLimit(4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sendingStatus: String {
        if !store.settings.shareDiagnostics { return "Off" }
        return telemetry.endpoint == nil ? "Kept on this iPhone" : "Automatic"
    }
}

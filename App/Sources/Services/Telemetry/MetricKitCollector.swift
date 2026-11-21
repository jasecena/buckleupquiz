import Foundation
import MetricKit

/// Crash, hang and resource reports from Apple's MetricKit (ADR-0020). iOS delivers them to
/// the app (usually the next day). They hold call stacks and device info, no personal data,
/// and are forwarded to `Telemetry` like any other event.
final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private weak var telemetry: Telemetry?

    @MainActor
    init(telemetry: Telemetry) {
        self.telemetry = telemetry
        super.init()
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var reports: [(String, String)] = []
        for payload in payloads {
            let kinds: [(String, [MXDiagnostic]?)] = [
                ("crash", payload.crashDiagnostics),
                ("hang", payload.hangDiagnostics),
                ("cpuException", payload.cpuExceptionDiagnostics),
                ("diskWriteException", payload.diskWriteExceptionDiagnostics),
                ("launch", payload.appLaunchDiagnostics),
            ]
            for (kind, diagnostics) in kinds {
                for diagnostic in diagnostics ?? [] {
                    reports.append((kind, String(decoding: diagnostic.jsonRepresentation(), as: UTF8.self)))
                }
            }
        }
        guard !reports.isEmpty else { return }
        Task { @MainActor [weak self, reports] in
            guard let telemetry = self?.telemetry else { return }
            for (kind, json) in reports {
                telemetry.record("metrickit.\(kind)", ["report": json], maxLength: Telemetry.maxReportLength)
            }
            await telemetry.flush()
        }
    }
}

import Foundation
import Testing
@testable import BuckleUpQuiz

@MainActor
struct TelemetryTests {
    final class Sent: @unchecked Sendable {
        var bodies: [Data] = []
        var status = 204
    }

    func makeTelemetry(enabled: Bool = true, sent: Sent = Sent()) -> Telemetry {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("telemetry-\(UUID()).json")
        return Telemetry(endpoint: URL(string: "https://example.invalid/t"), fileURL: url, isEnabled: { enabled },
                         send: { request in
                             sent.bodies.append(request.httpBody ?? Data())
                             return sent.status
                         })
    }

    @Test func queuesAndSendsInBatches() async throws {
        let sent = Sent()
        let telemetry = makeTelemetry(sent: sent)
        for i in 0..<25 { telemetry.record("voice.listenFailed", ["n": "\(i)"]) }
        await telemetry.flush()
        #expect(telemetry.pending.isEmpty)
        #expect(sent.bodies.count == 2, "20 + 5")
        let body = try JSONSerialization.jsonObject(with: sent.bodies[0]) as? [String: Any]
        #expect((body?["events"] as? [Any])?.count == 20)
        #expect(body?["device"] as? String != nil)
        #expect(body?.keys.contains("launch") == true)
    }

    @Test func keepsReportsWhenSendingFails() async {
        let sent = Sent()
        sent.status = 500
        let telemetry = makeTelemetry(sent: sent)
        telemetry.record("voice.micStartFailed", [:])
        await telemetry.flush()
        #expect(telemetry.pending.count == 1)
        #expect(telemetry.lastError == "Server said 500")
    }

    @Test func recordsNothingWhenTurnedOff() async {
        let telemetry = makeTelemetry(enabled: false)
        telemetry.record("voice.micStartFailed", [:])
        #expect(telemetry.pending.isEmpty)
    }

    @Test func capsTheQueueAndLongFields() {
        let telemetry = makeTelemetry()
        for _ in 0..<(Telemetry.maxQueued + 10) { telemetry.record("x", ["long": String(repeating: "a", count: 2000)]) }
        #expect(telemetry.pending.count == Telemetry.maxQueued)
        #expect(telemetry.pending[0].fields["long"]?.count == Telemetry.maxFieldLength)
        #expect(telemetry.pending[0].at.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) == 0)
    }

    @Test func survivesARestart() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("telemetry-\(UUID()).json")
        let first = Telemetry(endpoint: nil, fileURL: url, isEnabled: { true })
        first.record("content.loadFailed", ["error": "x"])
        let second = Telemetry(endpoint: nil, fileURL: url, isEnabled: { true })
        #expect(second.pending.map(\.name) == ["content.loadFailed"])
    }
}

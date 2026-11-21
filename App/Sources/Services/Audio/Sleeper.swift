/// Waiting, injectable so tests run instantly.
protocol Sleeper: Sendable {
    func sleep(seconds: Double) async throws
}

struct TaskSleeper: Sleeper {
    func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}

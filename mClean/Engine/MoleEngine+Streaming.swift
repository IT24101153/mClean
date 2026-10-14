import Foundation

extension MoleEngine {
    /// Runs a command and delivers its output lines on the main actor, in order.
    /// Cancelling the calling task interrupts the command.
    @MainActor
    func stream(
        _ arguments: [String],
        input: String? = nil,
        purpose: Purpose = .scan,
        onLine: (String) -> Void
    ) async throws -> MoleRun {
        let (lines, continuation) = AsyncStream<String>.makeStream()
        let engine = self
        let runner = Task.detached {
            defer { continuation.finish() }
            return try await engine.run(arguments, input: input, purpose: purpose) { continuation.yield($0) }
        }
        return try await withTaskCancellationHandler {
            for await line in lines {
                onLine(line)
            }
            return try await runner.value
        } onCancel: {
            runner.cancel()
        }
    }
}

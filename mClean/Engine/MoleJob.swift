import Foundation

/// The flow every cleaning screen shares: preview with a dry-run, review the
/// result, then run the real command.
@Observable
final class MoleJob {
    enum Phase: Equatable {
        case idle, previewing, ready, running, finished, failed(String)
    }

    private let previewArguments: [String]
    private let runArguments: [String]?

    private(set) var phase: Phase = .idle
    /// Output of the command that is running right now.
    private(set) var live = MoleReport()
    /// The last completed dry-run.
    private(set) var preview: MoleReport?
    /// The last completed real run.
    private(set) var result: MoleReport?
    private var task: Task<Void, Never>?

    /// - Parameter run: The real command, or nil when the screen acts on the preview itself.
    init(preview: [String], run: [String]?) {
        previewArguments = preview
        runArguments = run
    }

    func startPreview(with engine: MoleEngine, then: @escaping () -> Void = {}) {
        start(.previewing, engine: engine, arguments: previewArguments, purpose: .scan) { report in
            self.preview = report
            then()
            return .ready
        }
    }

    func startRun(with engine: MoleEngine, then: @escaping () -> Void = {}) {
        guard let runArguments else { return }
        start(.running, engine: engine, arguments: runArguments, purpose: .change) { report in
            self.result = report
            self.preview = nil
            then()
            return .finished
        }
    }

    func cancel() {
        task?.cancel()
    }

    func dismissResult() {
        result = nil
        phase = .idle
    }

    /// Forgets the preview, for when the screen changed things itself.
    func reset() {
        task?.cancel()
        preview = nil
        result = nil
        phase = .idle
    }

    private func start(_ working: Phase, engine: MoleEngine, arguments: [String], purpose: MoleEngine.Purpose,
                       completion: @escaping (MoleReport) -> Phase) {
        task?.cancel()
        live = MoleReport()
        phase = working
        task = Task {
            do {
                let run = try await engine.stream(arguments, purpose: purpose) { live.consume($0) }
                if run.succeeded || !live.summary.isEmpty {
                    phase = completion(live)
                } else {
                    phase = .failed(run.failureMessage)
                }
            } catch is CancellationError {
                // A stopped run leaves the preview out of date.
                if working == .running { preview = nil }
                phase = preview == nil ? .idle : .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

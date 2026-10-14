import Foundation

@Observable
final class AppsModel {
    enum Sort: String, CaseIterable, Identifiable {
        case size = "Size", name = "Name"
        var id: Self { self }
    }

    private(set) var apps: [InstalledApp]
    private(set) var isLoading = false
    private(set) var error: String?
    /// True once this launch has a fresh list from the engine.
    private var loaded = false

    /// The engine takes several seconds to list apps, so the last list is
    /// kept on disk and shown right away while a fresh one loads.
    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "mClean/apps.json")
    }

    init() {
        apps = (try? JSONDecoder().decode([InstalledApp].self, from: Data(contentsOf: Self.cacheURL))) ?? []
    }

    var sort: Sort = .size
    var query = ""

    var visibleApps: [InstalledApp] {
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleId.localizedCaseInsensitiveContains(query)
        }
        switch sort {
        case .size: return filtered.sorted { $0.bytes > $1.bytes }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var totalBytes: Int64 { apps.map(\.bytes).reduce(0, +) }

    func loadIfNeeded(with engine: MoleEngine) async {
        guard !loaded, !isLoading else { return }
        await load(with: engine)
    }

    func load(with engine: MoleEngine) async {
        isLoading = true
        error = nil
        do {
            apps = try await engine.json([InstalledApp].self, ["uninstall", "--list"])
            loaded = true
            saveCache()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func forget(_ app: InstalledApp) {
        apps.removeAll { $0.id == app.id }
        saveCache()
    }

    private func saveCache() {
        let url = Self.cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(apps).write(to: url, options: .atomic)
    }
}

/// One uninstall: preview the removal plan, then move everything to the Trash.
@Observable
final class UninstallFlow: Identifiable {
    enum Phase {
        case preparing
        case review(UninstallPlan)
        case removing
        case finished(MoleReport)
        case failed(String)
    }

    let app: InstalledApp
    private(set) var phase: Phase = .preparing
    private var task: Task<Void, Never>?

    var id: String { app.id }

    init(app: InstalledApp) {
        self.app = app
    }

    // Mole asks "Proceed? [y/N]" and then waits for Enter. "y" answers the
    // first; closing stdin answers the second with Enter.
    private static let confirmation = "y\n"

    func prepare(with engine: MoleEngine) {
        phase = .preparing
        task = Task {
            do {
                let run = try await engine.run(["uninstall", "--dry-run", app.uninstallName], input: Self.confirmation)
                let plan = UninstallPlan.parse(run.output)
                phase = plan.isEmpty ? .failed(run.failureMessage) : .review(plan)
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func uninstall(with engine: MoleEngine, onRemoved: @escaping () -> Void) {
        Notifier.requestPermission()
        phase = .removing
        task = Task {
            var report = MoleReport()
            do {
                let run = try await engine.stream(["uninstall", app.uninstallName], input: Self.confirmation,
                                                  purpose: .change) {
                    report.consume($0)
                }
                if report.summary.contains(where: { $0.hasPrefix("Removed ") }) {
                    onRemoved()
                    phase = .finished(report)
                    Notifier.postIfInBackground("\(app.name) was removed", "It's in the Trash with its related files.")
                } else if !report.summary.isEmpty {
                    phase = .finished(report)
                } else {
                    phase = .failed(run.failureMessage)
                }
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}

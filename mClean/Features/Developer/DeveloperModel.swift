import Foundation

/// Developer Junk finds build output and dependency folders with
/// `mole purge --dry-run`, then moves the ones you pick to the Trash.
@Observable
final class DeveloperModel {
    let job = MoleJob(preview: ["purge", "--dry-run"], run: nil)
    /// Paths of the folders to remove. Everything is selected after a scan.
    var selection: Set<String> = []
    private(set) var isTrashing = false
    private(set) var outcome: TrashBin.MoveOutcome?

    func scan(with engine: MoleEngine) {
        outcome = nil
        job.startPreview(with: engine) {
            self.selection = Set(self.artifacts.map(\.path))
            if self.totalBytes > 0 {
                Notifier.postIfInBackground("Project scan finished",
                                            "\(ByteSize.format(self.totalBytes)) in build folders and dependencies.")
            }
        }
    }

    var artifacts: [ReportedPath] {
        job.preview.map(PurgeOutput.artifacts(in:))?.sorted { $0.bytes > $1.bytes } ?? []
    }

    var selectedArtifacts: [ReportedPath] { artifacts.filter { selection.contains($0.path) } }
    var selectedBytes: Int64 { selectedArtifacts.map(\.bytes).reduce(0, +) }
    var allSelected: Bool { !artifacts.isEmpty && selection.count == artifacts.count }

    func toggleAll() {
        selection = allSelected ? [] : Set(artifacts.map(\.path))
    }

    var totalBytes: Int64 {
        job.preview?.summaryValue("Would free approximately").flatMap(ByteSize.parse)
            ?? artifacts.map(\.bytes).reduce(0, +)
    }

    var liveBytes: Int64 {
        PurgeOutput.artifacts(in: job.live).map(\.bytes).reduce(0, +)
    }

    var selectionHasDependencies: Bool {
        selectedArtifacts.contains { ArtifactKind(path: $0) == .dependencies }
    }

    func moveSelectedToTrash(using trash: TrashModel) async {
        Notifier.requestPermission()
        isTrashing = true
        let items = selectedArtifacts.map { (path: $0.expandedPath, size: $0.bytes) }
        let result = await trash.move(items)
        isTrashing = false
        outcome = result
        job.reset()
        selection = []
        Notifier.postIfInBackground("Developer junk moved to the Trash",
                                    "\(ByteSize.format(result.movedBytes)) from \(result.movedCount) folders.")
    }

    func dismissOutcome() {
        outcome = nil
    }
}

import Foundation

/// System Junk drives `mole clean`.
@Observable
final class JunkModel {
    let job = MoleJob(preview: ["clean", "--dry-run"], run: ["clean"])
    /// Every path the preview found, keyed by section title.
    private(set) var paths: [String: [ReportedPath]] = [:]

    func scan(with engine: MoleEngine, then: @escaping () -> Void = {}) {
        job.startPreview(with: engine) {
            self.paths = CleanList.load()
            if let bytes = self.cleanableBytes, bytes > 0 {
                Notifier.postIfInBackground("System Junk scan finished", "\(ByteSize.format(bytes)) is ready to clean.")
            }
            then()
        }
    }

    func clean(with engine: MoleEngine, onFinish: @escaping () -> Void) {
        Notifier.requestPermission()
        job.startRun(with: engine) {
            self.paths = [:]
            let freed = self.freedBytes.map { "Freed \(ByteSize.format($0))." } ?? "Your Mac is clean."
            Notifier.postIfInBackground("System Junk cleaned", freed)
            onFinish()
        }
    }

    // MARK: Preview

    var cleanableSections: [ReportSection] {
        (job.preview?.sections ?? []).compactMap { section in
            let items = section.meaningfulItems.filter { $0.state == .preview }
            return items.isEmpty ? nil : ReportSection(title: section.title, items: items)
        }
    }

    /// Big things Mole points out but never removes on its own.
    var reviewItems: [ReportItem] {
        job.preview?.allItems.filter { $0.state == .review } ?? []
    }

    var needsFullDiskAccess: Bool {
        (job.preview?.allItems ?? []).contains { $0.state == .warning && ($0.detail ?? "").contains("Full Disk Access") }
    }

    var cleanableBytes: Int64? {
        guard let preview = job.preview else { return nil }
        if let total = preview.summaryValue("Potential space").flatMap(ByteSize.parse) {
            return total
        }
        return cleanableSections.map(\.totalBytes).reduce(0, +)
    }

    var previewDetail: String? {
        guard let preview = job.preview, let items = preview.summaryValue("Items") else { return nil }
        let categories = preview.summaryValue("Categories")
        return categories.map { "\(items) items in \($0) categories" } ?? "\(items) items"
    }

    /// Running total while a command streams.
    var liveBytes: Int64 {
        job.live.allItems.filter { $0.state == .preview || $0.state == .done }.compactMap(\.bytes).reduce(0, +)
    }

    // MARK: Result

    var freedBytes: Int64? {
        guard let result = job.result else { return nil }
        if let tracked = result.summaryValue("Tracked cleanup").flatMap(ByteSize.parse) {
            return tracked
        }
        let total = result.allItems.filter { $0.state == .done }.compactMap(\.bytes).reduce(0, +)
        return total > 0 ? total : nil
    }
}

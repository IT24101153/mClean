import Foundation

/// Disk Space drives `mole analyze --json`, one folder at a time.
@Observable
final class SpaceModel {
    enum Mode: String, CaseIterable, Identifiable {
        case folders = "Folders", largeFiles = "Large Files"
        var id: Self { self }
    }

    /// Folders the user drilled into; the first is the disk overview.
    private(set) var trail: [DiskScan] = []
    private(set) var loadingName: String?
    private(set) var error: String?
    var mode: Mode = .folders

    private var task: Task<Void, Never>?
    private var stale = false
    /// Set when Mole's cached measurements can't be trusted any more.
    private var needsFreshScan = false

    var current: DiskScan? { trail.last }
    var isLoading: Bool { loadingName != nil }

    var entries: [DiskScan.Entry] {
        let all = current?.entries ?? []
        return current?.overview == true ? all.filter { $0.insight != true } : all
    }

    /// In the overview Mole flags well-known space hogs separately.
    var insights: [DiskScan.Entry] {
        current?.overview == true ? (current?.entries ?? []).filter { $0.insight == true } : []
    }

    var largeFiles: [DiskScan.LargeFile] { current?.largeFiles ?? [] }

    var currentTotal: Int64 {
        guard let current else { return 0 }
        if current.overview == true { return current.totalSize ?? 0 }
        return entries.map(\.size).reduce(0, +)
    }

    func loadIfNeeded(with engine: MoleEngine) {
        if trail.isEmpty || stale {
            open(nil, named: "your disk", with: engine)
        }
    }

    /// Opens a folder, or the disk overview when `path` is nil.
    func open(_ path: String?, named name: String, with engine: MoleEngine) {
        load(path, named: name, with: engine, replacingCurrent: false)
        mode = .folders
    }

    /// Measures the current folder again, ignoring Mole's cached sizes.
    func rescan(with engine: MoleEngine) {
        needsFreshScan = true
        guard let current, trail.count > 1 else {
            load(nil, named: "your disk", with: engine, replacingCurrent: false)
            return
        }
        load(current.path, named: (current.path as NSString).lastPathComponent, with: engine, replacingCurrent: true)
    }

    /// Full Disk Access just appeared: earlier measurements missed folders.
    func resetDiskScans() {
        needsFreshScan = true
        stale = true
    }

    private func load(_ path: String?, named name: String, with engine: MoleEngine, replacingCurrent: Bool) {
        task?.cancel()
        loadingName = name
        error = nil
        task = Task {
            do {
                if needsFreshScan {
                    await Task.detached { MoleCache.resetDiskScans() }.value
                    needsFreshScan = false
                }
                let arguments = ["analyze", "--json"] + (path.map { [$0] } ?? [])
                let scan = try await engine.json(DiskScan.self, arguments)
                if path == nil {
                    trail = [scan]
                    stale = false
                } else if replacingCurrent, !trail.isEmpty {
                    trail[trail.count - 1] = scan
                } else {
                    trail.append(scan)
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            loadingName = nil
        }
    }

    func go(to index: Int) {
        guard trail.indices.contains(index) else { return }
        task?.cancel()
        loadingName = nil
        trail.removeSubrange((index + 1)...)
    }

    func cancel() {
        task?.cancel()
        loadingName = nil
    }

    func invalidate() {
        stale = true
    }

    // MARK: Trash

    /// Only things inside the home folder, never the standard folders themselves.
    static func canTrash(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home + "/") else { return false }
        let parts = path.dropFirst(home.count + 1).split(separator: "/")
        guard let first = parts.first.map(String.init) else { return false }
        let standard: Set = ["Library", "Applications", "Desktop", "Documents", "Downloads",
                             "Movies", "Music", "Pictures", "Public"]
        if parts.count == 1 { return !standard.contains(first) }
        if first == "Library" { return parts.count >= 3 }
        return true
    }

    /// Moves an item to the Trash and takes its size out of every folder on screen.
    func moveToTrash(_ path: String, size: Int64) throws {
        try FileManager.default.trashItem(at: URL(filePath: path), resultingItemURL: nil)
        let removed = path
        trail = trail.map { scan in
            var scan = scan
            scan.entries = scan.entries?.compactMap { entry in
                guard entry.path != removed else { return nil }
                var entry = entry
                if removed.hasPrefix(entry.path + "/") {
                    entry.size = max(0, entry.size - size)
                }
                return entry
            }
            scan.largeFiles?.removeAll { $0.path == removed || $0.path.hasPrefix(removed + "/") }
            let scanRoot = scan.path == "/" ? "/" : scan.path + "/"
            if let total = scan.totalSize, removed.hasPrefix(scanRoot) {
                scan.totalSize = max(0, total - size)
            }
            return scan
        }
        // Mole would still report the old sizes from its cache.
        needsFreshScan = true
    }
}

import Foundation

/// What mClean did itself, for History. Mole's own history covers what Mole
/// removes, but not optimizations (Mole doesn't log their changes) or the
/// files mClean moves to the Trash directly.
@Observable
final class ActivityLog {
    struct Entry: Codable, Identifiable {
        enum Kind: String, Codable {
            case optimized, movedToTrash, emptiedTrash
        }

        var id = UUID()
        var date: Date
        var kind: Kind
        var title: String
        var detail: String
    }

    private(set) var entries: [Entry]

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "mClean/activity.json")
    }

    init() {
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: Self.fileURL))) ?? []
    }

    func record(_ kind: Entry.Kind, _ title: String, _ detail: String) {
        entries.insert(Entry(date: .now, kind: kind, title: title, detail: detail), at: 0)
        entries = Array(entries.prefix(200))
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}

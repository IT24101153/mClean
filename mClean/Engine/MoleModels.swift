import Foundation

// MARK: - mole status --json

nonisolated struct StatusSnapshot: Decodable, Sendable {
    struct Hardware: Decodable, Sendable {
        var model: String?
        var cpuModel: String?
        var totalRam: String?
        var diskSize: String?
        var osVersion: String?
    }

    struct CPU: Decodable, Sendable {
        var usage: Double?
        var coreCount: Int?
    }

    struct Memory: Decodable, Sendable {
        var used: Int64?
        var total: Int64?
        var usedPercent: Double?
        var pressure: String?
    }

    struct Disk: Decodable, Sendable {
        var mount: String
        var used: Int64?
        var total: Int64?
        var usedPercent: Double?
        var external: Bool?
        var purgeable: Int64?
    }

    struct Battery: Decodable, Sendable {
        var percent: Double?
        var status: String?
        var health: String?
        var cycleCount: Int?
    }

    var host: String?
    var uptime: String?
    var hardware: Hardware?
    var healthScore: Int?
    var healthScoreMsg: String?
    var cpu: CPU?
    var memory: Memory?
    var disks: [Disk]?
    var trashSize: Int64?
    var batteries: [Battery]?

    var startupDisk: Disk? { disks?.first { $0.mount == "/" } ?? disks?.first }

    /// The live stream starts with empty hardware fields; keep the last known ones.
    mutating func keepHardware(from previous: StatusSnapshot?) {
        if hardware?.model?.isEmpty ?? true, let known = previous?.hardware, !(known.model?.isEmpty ?? true) {
            hardware = known
        }
    }
}

// MARK: - mole uninstall --list (piped)

nonisolated struct InstalledApp: Codable, Sendable, Identifiable, Hashable {
    var name: String
    var bundleId: String
    var source: String
    var uninstallName: String
    var path: String
    var size: String

    var id: String { path }
    var bytes: Int64 { ByteSize.parse(size) ?? 0 }
    var displaySize: String { bytes > 0 ? ByteSize.format(bytes) : size }
    var isHomebrew: Bool { source == "Homebrew" }

    enum CodingKeys: String, CodingKey {
        case name, source, path, size
        case bundleId = "bundle_id"
        case uninstallName = "uninstall_name"
    }
}

// MARK: - mole analyze --json [path]

nonisolated struct DiskScan: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Identifiable, Hashable {
        var name: String
        var path: String
        var size: Int64
        var isDir: Bool?
        var insight: Bool?
        var lastAccess: String?

        var id: String { path }
        var isDirectory: Bool { isDir ?? true }

        enum CodingKeys: String, CodingKey {
            case name, path, size, insight
            case isDir = "is_dir"
            case lastAccess = "last_access"
        }
    }

    struct LargeFile: Decodable, Sendable, Identifiable, Hashable {
        var name: String
        var path: String
        var size: Int64

        var id: String { path }
    }

    var path: String
    var overview: Bool?
    var scanStatus: String?
    var totalSize: Int64?
    var entries: [Entry]?
    var largeFiles: [LargeFile]?

    enum CodingKeys: String, CodingKey {
        case path, overview, entries
        case scanStatus = "scan_status"
        case totalSize = "total_size"
        case largeFiles = "large_files"
    }
}

// MARK: - mole history --json

nonisolated struct CleanupHistory: Decodable, Sendable {
    struct Session: Decodable, Sendable, Identifiable {
        struct Actions: Decodable, Sendable {
            var removed: Int?
            var trashed: Int?
            var skipped: Int?
            var failed: Int?
            var rebuilt: Int?
            var other: Int?
        }

        var command: String
        var runId: String?
        var startedAt: String?
        var endedAt: String?
        var items: Int?
        var size: String?
        var operationCount: Int?
        var failedTasks: Int?
        var actions: Actions?

        /// Previews are logged as sessions too, and a preview whose task failed
        /// looks just like a real run that failed. Only recorded changes count.
        var changedSomething: Bool {
            (actions?.removed ?? 0) + (actions?.trashed ?? 0) + (actions?.rebuilt ?? 0) + (actions?.other ?? 0) > 0
        }

        var id: String { (runId?.isEmpty == false ? runId : nil) ?? "\(command)-\(startedAt ?? "")" }

        var startDate: Date? {
            guard let startedAt else { return nil }
            return Session.dateFormatter.date(from: startedAt)
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter
        }()
    }

    var sessions: [Session]
}

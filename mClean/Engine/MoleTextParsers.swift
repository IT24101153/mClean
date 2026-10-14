import Foundation

/// One path Mole reported, with its size.
nonisolated struct ReportedPath: Identifiable, Sendable, Hashable {
    var path: String
    var size: String?

    var id: String { path }
    var bytes: Int64 { size.flatMap(ByteSize.parse) ?? 0 }
    /// The size in the same style as the rest of the app.
    var displaySize: String? { bytes > 0 ? ByteSize.format(bytes) : size }
    var expandedPath: String { (path as NSString).expandingTildeInPath }
    var displayPath: String { (expandedPath as NSString).abbreviatingWithTildeInPath }
    var name: String { (expandedPath as NSString).lastPathComponent }
}

// MARK: - ~/.config/mole/clean-list.txt

/// Every path a `mole clean --dry-run` found, grouped by section:
///
///     === User essentials ===
///     /Users/me/Library/Caches/GeoServices  # 52.6MB
nonisolated enum CleanList {
    static var fileURL: URL {
        URL(filePath: NSHomeDirectory()).appending(path: ".config/mole/clean-list.txt")
    }

    static func load() -> [String: [ReportedPath]] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    static func parse(_ text: String) -> [String: [ReportedPath]] {
        var groups: [String: [ReportedPath]] = [:]
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("=== "), line.hasSuffix(" ===") {
                current = String(line.dropFirst(4).dropLast(4))
                continue
            }
            let parts = line.components(separatedBy: "  # ")
            let path = parts[0].trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/") || path.hasPrefix("~") else { continue }
            groups[current, default: []].append(ReportedPath(path: path, size: parts.count > 1 ? parts[1] : nil))
        }
        return groups
    }
}

// MARK: - mole uninstall <name> --dry-run

/// The removal plan Mole prints before it uninstalls an app.
nonisolated struct UninstallPlan: Sendable {
    var appTitle: String?
    var totalSize: String?
    var files: [ReportedPath] = []
    var systemFiles: [ReportedPath] = []
    var keptData: [ReportedPath] = []
    var warnings: [String] = []
    var matchedApps = 0

    var isEmpty: Bool { files.isEmpty && systemFiles.isEmpty }

    static func parse(_ output: String) -> UninstallPlan {
        var plan = UninstallPlan()
        enum Part { case none, files, kept }
        var part = Part.none

        for rawLine in output.split(separator: "\n") {
            let line = MoleText.clean(String(rawLine))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indented = line.hasPrefix("  ")

            if trimmed.hasPrefix("◎ Matched ") {
                plan.matchedApps = Int(trimmed.split(separator: " ")[2]) ?? 1
                continue
            }
            switch trimmed {
            case "Files to be removed:": part = .files; continue
            case "Personal data kept:": part = .kept; continue
            default: break
            }
            if trimmed.hasPrefix("➤ ") || trimmed.hasPrefix("=====") || trimmed.hasPrefix("D choose") {
                part = .none
                continue
            }

            switch part {
            case .none:
                continue
            case .files:
                if !indented, trimmed.hasPrefix("◎ ") {
                    let header = split(String(trimmed.dropFirst(2)))
                    plan.appTitle = header.path.replacingOccurrences(of: " [Brew]", with: "")
                    plan.totalSize = header.size
                } else if trimmed.hasPrefix("✓ ") {
                    let entry = split(String(trimmed.dropFirst(2)))
                    plan.files.append(ReportedPath(path: entry.path, size: entry.size))
                } else if trimmed.hasPrefix("◎ System: ") {
                    let entry = split(String(trimmed.dropFirst("◎ System: ".count)))
                    plan.systemFiles.append(ReportedPath(path: entry.path, size: entry.size))
                } else if trimmed.hasPrefix("◎ ") {
                    plan.warnings.append(String(trimmed.dropFirst(2)))
                }
            case .kept:
                if trimmed.hasPrefix("⊙ ") {
                    let entry = split(String(trimmed.dropFirst(2)))
                    plan.keptData.append(ReportedPath(path: entry.path, size: entry.size))
                }
            }
        }
        return plan
    }

    /// "~/Library/Caches/x , 135KB" -> ("~/Library/Caches/x", "135KB")
    private static func split(_ text: String) -> (path: String, size: String?) {
        guard let range = text.range(of: " , ", options: .backwards) else { return (text, nil) }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
    }
}

// MARK: - mole purge --dry-run

/// Lines like `✓ [DRY RUN] ~/Projects/app/node_modules, 300.1MB`.
nonisolated enum PurgeOutput {
    static func artifacts(in report: MoleReport) -> [ReportedPath] {
        report.allItems.compactMap { item in
            guard item.state == .done else { return nil }
            var text = item.title
            if text.hasPrefix("[DRY RUN] ") { text.removeFirst("[DRY RUN] ".count) }
            guard text.hasPrefix("~") || text.hasPrefix("/") else { return nil }
            guard let comma = text.range(of: ", ", options: .backwards) else {
                return ReportedPath(path: text, size: nil)
            }
            return ReportedPath(path: String(text[..<comma.lowerBound]), size: String(text[comma.upperBound...]))
        }
    }
}

// MARK: - Optimize task wording

nonisolated enum TaskStatus {
    case willRun, healthy, skipped, unavailable, attention

    /// Mole marks every dry-run line with the same arrow, so read the wording.
    init(_ task: ReportSection) {
        let states = task.items.map(\.state)
        let text = task.items.map(\.title).joined(separator: " ").lowercased()
        if states.contains(.warning) || states.contains(.error) {
            self = .attention
        } else if text.contains("not available") || text.contains("not readable") || states.allSatisfy({ $0 == .skipped }) {
            self = .unavailable
        } else if task.items.allSatisfy({ $0.title.lowercased().contains("skipped") }) {
            self = .skipped
        } else if task.items.allSatisfy({ Self.soundsHealthy($0.title.lowercased()) }) {
            self = .healthy
        } else {
            self = .willRun
        }
    }

    private static func soundsHealthy(_ text: String) -> Bool {
        ["already", "valid", "healthy", "verified", "optimal", "clean", "no ", "skipped"].contains { text.contains($0) }
    }
}

// MARK: - Purge artifact kinds

nonisolated enum ArtifactKind {
    case dependencies, build

    private static let dependencyFolders: Set = [
        "node_modules", "Pods", "venv", ".venv", "vendor", "bower_components", "Carthage", ".dart_tool",
    ]

    init(path: ReportedPath) {
        self = Self.dependencyFolders.contains(path.name) ? .dependencies : .build
    }

    var label: String {
        switch self {
        case .dependencies: "Dependencies"
        case .build: "Build output"
        }
    }
}

import Foundation

/// Turns Mole's plain-text progress output into sections and items.
///
/// Mole prints the same shape for clean, optimize, purge and uninstall:
///
///     ➤ Browsers
///       → Chrome cache · 31 items, 1.2GB dry
///       ◎ Trash · skipped, grant Full Disk Access to your terminal
///     ======================================================================
///     Dry run complete - no changes made
///     Potential space: 1.60GB | Items: 188 | Categories: 7
///     ======================================================================
nonisolated struct MoleReport: Sendable {
    var preamble: [ReportItem] = []
    var sections: [ReportSection] = []
    var summary: [String] = []
    var notes: [String] = []
    private var inSummary = false

    var allItems: [ReportItem] { preamble + sections.flatMap(\.items) }

    /// Title of the section Mole is working on right now.
    var currentStep: String? { sections.last?.title }

    mutating func consume(_ rawLine: String) {
        let line = MoleText.clean(rawLine)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("=====") {
            inSummary.toggle()
            return
        }
        if inSummary {
            summary.append(trimmed)
            return
        }
        if trimmed.hasPrefix("➤ ") {
            sections.append(ReportSection(title: String(trimmed.dropFirst(2))))
            return
        }
        if let item = ReportItem(line: trimmed) {
            if sections.isEmpty {
                preamble.append(item)
            } else {
                sections[sections.count - 1].items.append(item)
            }
            return
        }
        notes.append(trimmed)
    }

    /// The first summary line, e.g. "Cleanup complete".
    var summaryTitle: String? { summary.first }

    /// Summary lines meant for people, without CLI hints like "Use mo clean --whitelist".
    var summaryDetails: [String] {
        summary.dropFirst().filter { line in
            !line.contains(" mo ") && !line.hasPrefix("mo ") && !line.contains("--")
                && !line.hasPrefix("Detailed file list")
        }
    }

    /// Reads a labelled value out of the summary, e.g. `summaryValue("Potential space")`.
    func summaryValue(_ label: String) -> String? {
        for line in summary {
            for part in line.components(separatedBy: " | ") {
                let pieces = part.components(separatedBy: ": ")
                if pieces.count >= 2, pieces[0].hasSuffix(label) {
                    return pieces.dropFirst().joined(separator: ": ")
                }
            }
        }
        return nil
    }
}

nonisolated struct ReportSection: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var items: [ReportItem] = []

    /// Items that represent real work, without "Nothing to clean" placeholders.
    var meaningfulItems: [ReportItem] { items.filter { !$0.isPlaceholder } }

    var totalBytes: Int64 { items.compactMap(\.bytes).reduce(0, +) }
}

nonisolated struct ReportItem: Identifiable, Sendable, Hashable {
    enum State: Sendable, Hashable {
        case done, preview, warning, review, error, info, skipped
    }

    let id = UUID()
    var state: State
    var title: String
    var detail: String?
    var bytes: Int64?

    init(state: State, title: String, detail: String? = nil, bytes: Int64? = nil) {
        self.state = state
        self.title = title
        self.detail = detail
        self.bytes = bytes
    }

    /// Parses `✓ Title · detail` style lines. Returns nil for plain text.
    init?(line: String) {
        guard let icon = line.first, line.dropFirst().first == " " else { return nil }
        let state: State
        switch icon {
        case "✓": state = .done
        case "→": state = .preview
        case "◎": state = .warning
        case "⊙": state = .review
        case "☻": state = .error
        case "•", "ℹ": state = .info
        case "-": state = .skipped
        default: return nil
        }

        let body = String(line.dropFirst(2))
        if let range = body.range(of: " · ") {
            title = String(body[..<range.lowerBound])
            var rest = String(body[range.upperBound...])
            if rest.hasSuffix(" dry") { rest.removeLast(4) }
            detail = rest
        } else {
            title = body
            detail = nil
        }
        self.state = state
        bytes = detail.flatMap(ByteSize.parse)
    }

    var isPlaceholder: Bool {
        title == "Nothing to clean" || title.hasPrefix("Great! No ")
    }

    /// A filesystem path mentioned in the detail, e.g. "~/.android/avd".
    var mentionedPath: String? {
        guard let detail else { return nil }
        let candidate = detail.components(separatedBy: " · ").last?.trimmingCharacters(in: .whitespaces)
        guard let candidate, candidate.hasPrefix("~/") || candidate.hasPrefix("/") else { return nil }
        return (candidate as NSString).expandingTildeInPath
    }
}

nonisolated enum MoleText {
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]")

    /// Strips terminal escape codes and carriage returns.
    static func clean(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "\r", with: "")
        if text.contains("\u{1B}") {
            let range = NSRange(text.startIndex..., in: text)
            text = ansi.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        return text
    }

    /// Mole addresses a terminal user; reword the few hints that leak through.
    static func friendly(_ text: String) -> String {
        var text = text
        if let first = text.first, "✓→◎⊙☻•↳ℹ".contains(first), text.dropFirst().first == " " {
            text.removeFirst(2)
        }
        return text.replacingOccurrences(of: "to your terminal", with: "to mClean")
            .replacingOccurrences(of: "your terminal", with: "mClean")
    }
}

import SwiftUI

@Observable
final class HistoryModel {
    private(set) var sessions: [CleanupHistory.Session] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var stale = true

    func loadIfNeeded(with engine: MoleEngine) async {
        guard stale, !isLoading else { return }
        isLoading = true
        do {
            let history = try await engine.json(CleanupHistory.self, ["history", "--json", "--limit", "100"], snakeCase: true)
            sessions = history.sessions.filter(\.changedSomething)
            error = nil
            stale = false
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func invalidate() {
        stale = true
    }
}

struct HistoryView: View {
    @Environment(AppState.self) private var state

    private var model: HistoryModel { state.history }

    /// Mole's sessions and mClean's own actions, newest first.
    private var rows: [HistoryRow] {
        let mole = model.sessions.map(HistoryRow.init(session:))
        let own = state.activity.entries.map(HistoryRow.init(entry:))
        return (mole + own).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Everything mClean has cleaned, newest first.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 16)
            Divider()

            if rows.isEmpty {
                Group {
                    if model.isLoading {
                        ProgressView()
                    } else if let error = model.error {
                        ContentUnavailableView("Couldn't read history", systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    } else {
                        ContentUnavailableView("Nothing yet", systemImage: "clock",
                                               description: Text("Cleanups you run will show up here."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { row in
                    HistoryRowView(row: row)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .task {
            guard let engine = state.engine else { return }
            await model.loadIfNeeded(with: engine)
        }
    }
}

private struct HistoryRow: Identifiable {
    let id: String
    let date: Date?
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    init(session: CleanupHistory.Session) {
        let screen: Screen = switch session.command {
        case "clean": .junk
        case "uninstall": .apps
        case "optimize": .optimize
        case "purge": .developer
        case "installer": .installers
        default: .history
        }
        id = "mole-" + session.id
        date = session.startDate
        symbol = screen.symbol
        tint = screen.tint
        title = switch session.command {
        case "clean": "System Junk cleaned"
        case "uninstall": "Apps uninstalled"
        case "optimize": "Mac optimized"
        case "purge": "Developer junk removed"
        case "installer": "Installers removed"
        default: session.command.capitalized
        }
        var parts: [String] = []
        if let items = session.items, items > 0 { parts.append("\(items) items") }
        if let bytes = session.size.flatMap(ByteSize.parse), bytes > 0 { parts.append(ByteSize.format(bytes)) }
        if let failed = session.failedTasks, failed > 0 { parts.append("\(failed) skipped") }
        detail = parts.joined(separator: " · ")
    }

    init(entry: ActivityLog.Entry) {
        id = entry.id.uuidString
        date = entry.date
        title = entry.title
        detail = entry.detail
        switch entry.kind {
        case .optimized:
            symbol = Screen.optimize.symbol
            tint = Screen.optimize.tint
        case .movedToTrash:
            symbol = "trash"
            tint = .secondary
        case .emptiedTrash:
            symbol = "trash.slash"
            tint = .secondary
        }
    }
}

private struct HistoryRowView: View {
    let row: HistoryRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .foregroundStyle(row.tint)
                .frame(width: 32, height: 32)
                .background(row.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let date = row.date {
                Text(date, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                    .help(date.formatted(date: .complete, time: .shortened))
            }
        }
        .padding(.vertical, 4)
    }
}

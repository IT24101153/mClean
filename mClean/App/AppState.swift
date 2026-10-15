import SwiftUI

enum Screen: String, CaseIterable, Identifiable, Hashable {
    case overview, junk, apps, space, installers, audio, optimize, developer, history

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .junk: "System Junk"
        case .apps: "Applications"
        case .space: "Disk Space"
        case .installers: "Installers"
        case .audio: "Audio Plugins"
        case .optimize: "Optimize"
        case .developer: "Developer Junk"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .junk: "sparkles"
        case .apps: "square.grid.2x2"
        case .space: "chart.pie"
        case .installers: "shippingbox"
        case .audio: "pianokeys"
        case .optimize: "bolt.heart"
        case .developer: "hammer"
        case .history: "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .overview: .accentColor
        case .junk: .green
        case .apps: .blue
        case .space: .indigo
        case .installers: .pink
        case .audio: .purple
        case .optimize: .orange
        case .developer: .teal
        case .history: .gray
        }
    }

    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((Screen.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

/// App-wide state. Feature models live here so their results survive
/// switching between screens.
@Observable
final class AppState {
    var screen: Screen = .overview
    let engine: MoleEngine?

    let status: StatusModel
    let permissions = PermissionMonitor()
    let trash = TrashModel()
    let activity = ActivityLog()
    let protection = ProtectionModel()
    let junk = JunkModel()
    let apps = AppsModel()
    let space = SpaceModel()
    let installers = InstallersModel()
    let audio = AudioModel()
    let optimize = OptimizeModel()
    let developer = DeveloperModel()
    let history = HistoryModel()

    init() {
        let engine = MoleEngine.locate()
        self.engine = engine
        status = StatusModel(engine: engine)

        // Disk measurements taken without Full Disk Access miss folders.
        if permissions.gainedAccessSinceLastLaunch {
            space.resetDiskScans()
        }
        permissions.remember()
        permissions.onAccessGranted = { [space] in space.resetDiskScans() }
    }

    /// Call after anything that frees space so the numbers stay honest.
    func didFreeSpace() {
        Task { await status.refresh() }
        history.invalidate()
        space.invalidate()
    }

    /// The best known size of the Trash. Mole can only measure it with Full
    /// Disk Access, so what mClean moved there itself counts too.
    var trashBytes: Int64 {
        max(status.snapshot?.trashSize ?? 0, trash.addedThisSession)
    }

    /// Returns a message when something went wrong, nil on success.
    func emptyTrash() async -> String? {
        let known = trashBytes
        let problem = await trash.empty()
        if problem == nil || problem?.contains("locked") == true {
            activity.record(.emptiedTrash, "Trash emptied", known > 0 ? "Freed \(ByteSize.format(known))" : "")
        }
        await status.refresh()
        return problem
    }

    /// Records files mClean moved to the Trash itself, for History.
    func recordTrash(_ outcome: TrashBin.MoveOutcome, from source: String) {
        guard outcome.movedCount > 0 else { return }
        let items = outcome.movedCount == 1 ? "1 item" : "\(outcome.movedCount) items"
        activity.record(.movedToTrash, "\(source) moved to the Trash",
                        "\(items) · \(ByteSize.format(outcome.movedBytes))")
    }
}

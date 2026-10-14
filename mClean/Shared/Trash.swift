import SwiftUI

/// Moving things to the Trash and emptying it.
nonisolated enum TrashBin {
    struct MoveOutcome: Sendable {
        var movedBytes: Int64 = 0
        var movedCount = 0
        var failures: [String] = []
    }

    static var folder: URL { URL(filePath: NSHomeDirectory()).appending(path: ".Trash") }

    /// Moves each item that still exists inside the home folder. Slow work, so call it off the main thread.
    static func move(_ items: [(path: String, size: Int64)]) -> MoveOutcome {
        var outcome = MoveOutcome()
        let home = NSHomeDirectory() + "/"
        for item in items {
            let path = (item.path as NSString).expandingTildeInPath
            guard path.hasPrefix(home), FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.trashItem(at: URL(filePath: path), resultingItemURL: nil)
                outcome.movedBytes += item.size
                outcome.movedCount += 1
            } catch {
                outcome.failures.append((path as NSString).lastPathComponent)
            }
        }
        return outcome
    }

    /// Deletes everything in the Trash permanently. Needs Full Disk Access.
    /// Returns how many items couldn't be deleted (locked or in use).
    static func empty() throws -> Int {
        let items = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var failed = 0
        for item in items {
            do {
                try FileManager.default.removeItem(at: item)
            } catch {
                failed += 1
            }
        }
        return failed
    }
}

@Observable
final class TrashModel {
    /// What mClean put in the Trash since it was last emptied. Mole's status
    /// report can't see into the Trash without Full Disk Access.
    private(set) var addedThisSession: Int64 = 0
    private(set) var isEmptying = false

    func didTrash(_ bytes: Int64) {
        addedThisSession += bytes
    }

    func move(_ items: [(path: String, size: Int64)]) async -> TrashBin.MoveOutcome {
        let outcome = await Task.detached { TrashBin.move(items) }.value
        didTrash(outcome.movedBytes)
        return outcome
    }

    /// Returns a message for the user when something went wrong, nil on success.
    func empty() async -> String? {
        isEmptying = true
        defer { isEmptying = false }
        do {
            let failed = try await Task.detached { try TrashBin.empty() }.value
            addedThisSession = 0
            return failed == 0 ? nil : "\(failed) item\(failed == 1 ? "" : "s") couldn't be deleted because they're locked or in use."
        } catch {
            return "mClean needs Full Disk Access to empty the Trash. You can also empty it from the Dock."
        }
    }
}

/// "Empty Trash" with its own confirmation, for wherever freed space should show up.
struct EmptyTrashButton: View {
    var bytes: Int64
    var compact = false

    @Environment(AppState.self) private var state
    @State private var confirming = false
    @State private var problem: String?

    var body: some View {
        Button {
            confirming = true
        } label: {
            if state.trash.isEmptying {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Emptying…")
                }
            } else if compact {
                Label("Empty Trash · \(ByteSize.format(bytes))", systemImage: "trash")
            } else {
                Text("Empty Trash")
            }
        }
        .disabled(state.trash.isEmptying)
        .alert("Empty the Trash?", isPresented: $confirming) {
            Button("Empty Trash", role: .destructive) {
                Task { problem = await state.emptyTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bytes > 0
                 ? "Everything in the Trash (\(ByteSize.format(bytes))) will be deleted permanently. This can't be undone."
                 : "Everything in the Trash will be deleted permanently. This can't be undone.")
        }
        .alert("Couldn't empty the Trash", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }
}

/// The finish line after moving things to the Trash, with the step that frees the space.
struct MovedToTrashView: View {
    let tint: Color
    let outcome: TrashBin.MoveOutcome
    let onDone: () -> Void

    @Environment(AppState.self) private var state

    var body: some View {
        FeatureHero(symbol: "checkmark", tint: tint,
                    title: "Moved \(ByteSize.format(outcome.movedBytes)) to the Trash",
                    message: message) {
            HStack(spacing: 10) {
                EmptyTrashButton(bytes: state.trashBytes)
                    .controlSize(.extraLarge)
                    .buttonBorderShape(.capsule)
                Button("Done", action: onDone)
                    .primaryAction(tint: tint)
            }
        }
    }

    private var message: String {
        var lines = ["Empty the Trash to free the space. Until then you can still put things back."]
        if !outcome.failures.isEmpty {
            lines.append("Couldn't move: \(outcome.failures.prefix(3).joined(separator: ", "))"
                         + (outcome.failures.count > 3 ? " and \(outcome.failures.count - 3) more" : ""))
        }
        return lines.joined(separator: "\n")
    }
}

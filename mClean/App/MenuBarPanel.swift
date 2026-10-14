import SwiftUI

/// The menu bar window: free space at a glance, plus a quick clean.
struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var trashProblem: String?

    private var snapshot: StatusSnapshot? { state.status.snapshot }
    private var junk: JunkModel { state.junk }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BrandMark(size: 22)
                Spacer()
                if let score = snapshot?.healthScore {
                    Text("Health \(score)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(score >= 80 ? .green : score >= 60 ? .yellow : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            disk

            Divider()
            junkRow
            if state.trashBytes > 0 {
                trashRow
            }
            Divider()

            HStack {
                Button("Open mClean") { open(.overview) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
        .task { await state.status.refresh() }
    }

    private var disk: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let disk = snapshot?.startupDisk, let used = disk.used, let total = disk.total, total > 0 {
                let fraction = Double(used) / Double(total)
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteSize.format(total - used))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text("free of \(ByteSize.format(total))")
                        .foregroundStyle(.secondary)
                }
                CapacityBar(fraction: fraction, tint: fraction > 0.9 ? .red : .accentColor, height: 6)
            } else {
                Text("Measuring…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: System Junk

    @ViewBuilder
    private var junkRow: some View {
        HStack(spacing: 10) {
            Image(systemName: Screen.junk.symbol)
                .foregroundStyle(Screen.junk.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("System Junk")
                    .font(.headline)
                Text(junkStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            junkAction
        }
    }

    private var junkStatus: String {
        switch junk.job.phase {
        case .idle: "Scan for caches and logs"
        case .previewing: junk.liveBytes > 0 ? "Scanning… \(ByteSize.format(junk.liveBytes)) so far" : "Scanning…"
        case .ready: "\(ByteSize.format(junk.cleanableBytes ?? 0)) ready to clean"
        case .running: "Cleaning…"
        case .finished: junk.freedBytes.map { "Freed \(ByteSize.format($0))" } ?? "Clean"
        case .failed: "Couldn't finish. Open mClean for details."
        }
    }

    @ViewBuilder
    private var junkAction: some View {
        switch junk.job.phase {
        case .previewing, .running:
            ProgressView().controlSize(.small)
        case .ready:
            HStack(spacing: 6) {
                Button("Review") { open(.junk) }
                ConfirmingButton(title: "Clean", confirmTitle: "Clean Now?") {
                    guard let engine = state.engine else { return }
                    junk.clean(with: engine) { state.didFreeSpace() }
                }
                .disabled((junk.cleanableBytes ?? 0) == 0)
            }
        case .finished:
            Button("Scan Again") {
                junk.job.dismissResult()
                scan()
            }
        case .idle, .failed:
            Button("Scan", action: scan)
        }
    }

    private func scan() {
        guard let engine = state.engine else { return }
        junk.scan(with: engine) { state.protection.scanned() }
    }

    // MARK: Trash

    private var trashRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trash")
                    .font(.headline)
                Text(trashProblem ?? ByteSize.format(state.trashBytes))
                    .font(.caption)
                    .foregroundStyle(trashProblem == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
            Spacer()
            if state.trash.isEmptying {
                ProgressView().controlSize(.small)
            } else {
                ConfirmingButton(title: "Empty", confirmTitle: "Empty Now?") {
                    Task { trashProblem = await state.emptyTrash() }
                }
            }
        }
    }

    private func open(_ screen: Screen) {
        state.screen = screen
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// A destructive button that asks for a second click instead of an alert,
/// which a menu bar window can't show reliably.
private struct ConfirmingButton: View {
    let title: String
    let confirmTitle: String
    let action: () -> Void

    @State private var armed = false

    var body: some View {
        Button(armed ? confirmTitle : title) {
            if armed {
                armed = false
                action()
            } else {
                armed = true
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    armed = false
                }
            }
        }
        .tint(armed ? .red : nil)
        .buttonStyle(.borderedProminent)
    }
}

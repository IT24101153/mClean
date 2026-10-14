import SwiftUI

/// Shown once on first launch: what mClean does, and the one permission it needs.
struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                BrandMark(size: 64)
                Text("Clean your Mac without the guesswork.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 14) {
                Point(symbol: "eye", tint: .green, title: "Preview first",
                      text: "Every cleanup shows exactly what it found before anything is removed.")
                Point(symbol: "trash", tint: .blue, title: "Recoverable where it matters",
                      text: "Apps, folders and files you delete go to the Trash, so you can put them back.")
                Point(symbol: "lock.shield", tint: .indigo, title: "Your rules",
                      text: "Mark caches you want kept, and mClean never touches them.")
            }
            .frame(maxWidth: 420, alignment: .leading)

            fullDiskAccess

            Button("Get Started") { dismiss() }
                .primaryAction(tint: .accentColor)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 520)
    }

    private var fullDiskAccess: some View {
        let granted = state.permissions.hasFullDiskAccess
        return VStack(alignment: .leading, spacing: 10) {
            Label(granted ? "Full Disk Access is on" : "Recommended: Full Disk Access",
                  systemImage: granted ? "checkmark.circle.fill" : "lock.open")
                .font(.headline)
                .foregroundStyle(granted ? .green : .primary)
            Text(granted
                 ? "mClean can reach the Trash and every folder it measures."
                 : "Lets mClean empty the Trash and measure every folder. Turn on mClean in Settings, then reopen it. You can do this later from mClean's Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !granted {
                HStack {
                    Button("Open Settings", action: Permissions.openFullDiskAccessSettings)
                    Button("Reopen mClean", action: Permissions.relaunch)
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .card(padding: 14)
    }
}

private struct Point: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

import AppKit
import SwiftUI

enum Permissions {
    /// Places macOS opens only to apps with Full Disk Access. Not every Mac has
    /// all of them (the user TCC database is gone on recent macOS), so any one
    /// that exists and opens is enough.
    private static var protectedProbes: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Safari",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/Library/Containers/com.apple.stocks",
            "\(home)/Library/Cookies",
            "\(home)/.Trash",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
    }

    static var hasFullDiskAccess: Bool {
        let fileManager = FileManager.default
        for path in protectedProbes {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if (try? fileManager.contentsOfDirectory(atPath: path)) != nil { return true }
            } else if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// macOS applies a new Full Disk Access grant only after the app restarts.
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

/// Keeps the Full Disk Access state current while the app runs.
@Observable
final class PermissionMonitor {
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess
    /// Called when access appears, so results measured without it can be redone.
    @ObservationIgnored var onAccessGranted: (() -> Void)?

    private static let lastKnownKey = "lastKnownFullDiskAccess"

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// True when this launch has access and the previous one didn't.
    var gainedAccessSinceLastLaunch: Bool {
        hasFullDiskAccess && !UserDefaults.standard.bool(forKey: Self.lastKnownKey)
    }

    func refresh() {
        let previous = hasFullDiskAccess
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        UserDefaults.standard.set(hasFullDiskAccess, forKey: Self.lastKnownKey)
        if hasFullDiskAccess && !previous {
            onAccessGranted?()
        }
    }

    func remember() {
        UserDefaults.standard.set(hasFullDiskAccess, forKey: Self.lastKnownKey)
    }
}

/// Mole's own caches that mClean may need to reset.
nonisolated enum MoleCache {
    /// Mole keeps disk measurements for up to a week, including ones taken
    /// without Full Disk Access or before mClean moved something to the Trash.
    /// Only the analyzer folder is removed; Mole keeps other state next to it.
    static func resetDiskScans() {
        let folder = URL(filePath: NSHomeDirectory()).appending(path: ".cache/mole/analyzer")
        guard folder.lastPathComponent == "analyzer",
              folder.deletingLastPathComponent().path.hasSuffix("/.cache/mole")
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

/// A one-line reminder where Full Disk Access is missing. The welcome screen explains it.
struct FullDiskAccessNotice: View {
    let reason: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Open Settings", action: Permissions.openFullDiskAccessSettings)
            Button("Reopen", action: Permissions.relaunch)
                .help("macOS applies Full Disk Access after mClean restarts")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

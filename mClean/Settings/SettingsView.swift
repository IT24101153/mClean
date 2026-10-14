import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var engineVersion: String?
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("didShowWelcome") private var didShowWelcome = false

    private static let configFolder = URL(filePath: NSHomeDirectory()).appending(path: ".config/mole")

    var body: some View {
        Form {
            Section {
                HStack {
                    BrandMark(size: 44)
                    Spacer()
                    Text("Version \(appVersion)")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("General") {
                Toggle("Show mClean in the menu bar", isOn: $showMenuBarExtra)
                LabeledContent("Welcome screen") {
                    Button("Show Again") { didShowWelcome = false }
                }
            }

            Section("Permissions") {
                let hasFullDiskAccess = state.permissions.hasFullDiskAccess
                LabeledContent("Full Disk Access") {
                    HStack {
                        Label(hasFullDiskAccess ? "Granted" : "Not granted",
                              systemImage: hasFullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(hasFullDiskAccess ? .green : .orange)
                        if !hasFullDiskAccess {
                            Button("Open Settings", action: Permissions.openFullDiskAccessSettings)
                            Button("Reopen", action: Permissions.relaunch)
                        }
                    }
                }
                Text("Lets mClean empty the Trash and measure protected folders. After turning it on, reopen mClean. Administrator tasks ask for your password each time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Protection") {
                LabeledContent("Protected paths") {
                    Button("Show in Finder") { open(Self.configFolder.appending(path: "whitelist")) }
                }
                LabeledContent("Project folders") {
                    Button("Show in Finder") { open(Self.configFolder.appending(path: "purge_paths")) }
                }
                Text("Advanced: the engine's lists of protected paths and project folders, one path per line. A protected-paths file you create replaces the engine's optional defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Engine") {
                LabeledContent("Version", value: engineVersion ?? "…")
                LabeledContent("Location") {
                    Text(state.engine.map { $0.isBundled ? "Built in" : $0.executableURL.path } ?? "Missing")
                        .textSelection(.enabled)
                }
                Link("Powered by Mole, open source under GPL-3.0",
                     destination: URL(string: "https://github.com/tw93/Mole")!)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            engineVersion = await state.engine?.version()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Reveals a config file, or its folder when the file doesn't exist yet.
    private func open(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(at: Self.configFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Self.configFolder)
        }
    }
}

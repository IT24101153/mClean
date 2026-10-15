import SwiftUI

/// Shows exactly what uninstalling plug-ins removes before anything moves.
struct PluginUninstallSheet: View {
    let plugins: [AudioPlugin]
    let onConfirm: (_ bundles: [PluginBundle], _ related: [PluginRelatedFile]) -> Void

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var related: [PluginRelatedFile] = []
    @State private var loading = true
    @State private var includeSettings = true
    @State private var includePresets = false

    private var bundles: [PluginBundle] { plugins.flatMap(\.bundles) }
    private var settings: [PluginRelatedFile] { related.filter { !$0.isPersonal } }
    private var presets: [PluginRelatedFile] { related.filter(\.isPersonal) }

    private var chosenRelated: [PluginRelatedFile] {
        (includeSettings ? settings : []) + (includePresets ? presets : [])
    }

    private var totalBytes: Int64 {
        bundles.map(\.size).reduce(0, +) + chosenRelated.map(\.size).reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plugins.count == 1 ? "Uninstall \(plugins[0].name)" : "Uninstall \(plugins.count) plugins")
                    .font(.title2.weight(.semibold))
                Text("\(ByteSize.format(totalBytes)) will be moved to the Trash.")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()

            List {
                let uninstallers = plugins.compactMap { plugin in
                    state.audio.uninstaller(for: plugin).map { (plugin, $0) }
                }
                ForEach(uninstallers, id: \.1) { plugin, app in
                    NoticeBanner(symbol: "info.circle",
                                 text: "\(plugin.vendor) has its own uninstaller for \(plugin.name), which can also remove licenses and sound content.",
                                 tint: .blue) {
                        Button("Open") { NSWorkspace.shared.open(URL(filePath: app)) }
                            .controlSize(.small)
                    }
                    .listRowSeparator(.hidden)
                }

                Section("Plugin files") {
                    ForEach(plugins) { plugin in
                        ForEach(plugin.bundles) { bundle in
                            HStack(spacing: 8) {
                                FormatBadge(format: bundle.format)
                                    .frame(width: 40, alignment: .leading)
                                PathRow(path: ReportedPath(path: bundle.path, size: ByteSize.format(bundle.size)))
                            }
                        }
                    }
                }

                if loading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Looking for settings and presets…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !settings.isEmpty {
                        Section {
                            Toggle("Also remove settings and caches (\(ByteSize.format(settings.map(\.size).reduce(0, +))))",
                                   isOn: $includeSettings)
                            ForEach(settings) { PathRow(path: ReportedPath(path: $0.path, size: ByteSize.format($0.size))) }
                        }
                    }
                    if !presets.isEmpty {
                        Section {
                            Toggle("Also remove presets (\(ByteSize.format(presets.map(\.size).reduce(0, +))))",
                                   isOn: $includePresets)
                            ForEach(presets) { PathRow(path: ReportedPath(path: $0.path, size: ByteSize.format($0.size))) }
                        } footer: {
                            Text("Presets you saved yourself live here too, so they're kept unless you choose otherwise.")
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                if plugins.contains(where: \.needsAdmin) {
                    Label("Asks for your administrator password", systemImage: "lock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) {
                    onConfirm(bundles, chosenRelated)
                }
                .keyboardShortcut(.defaultAction)
                .tint(.red)
                .disabled(loading)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 600, height: 560)
        .task {
            let plugins = plugins
            related = await Task.detached {
                plugins.flatMap(AudioPluginScanner.relatedFiles(for:))
            }.value
            loading = false
        }
    }
}

import SwiftUI

struct AudioView: View {
    @Environment(AppState.self) private var state
    @State private var uninstalling: [AudioPlugin] = []
    @State private var confirmingAAX = false
    @State private var confirmingCaches = false
    @State private var presetSelection: Set<String> = []

    private var model: AudioModel { state.audio }
    private let tint = Screen.audio.tint

    var body: some View {
        Group {
            if let outcome = model.outcome {
                MovedToTrashView(tint: tint, outcome: outcome) { model.dismissOutcome() }
            } else {
                switch model.phase {
                case .idle:
                    FeatureHero(symbol: Screen.audio.symbol, tint: tint, title: "Audio Plugins",
                                message: "Find your Audio Unit, VST, VST3, AAX and CLAP plugins, remove the ones you don't use, and reset plugin caches.") {
                        Button("Scan Plugins", action: model.scan)
                            .primaryAction(tint: tint)
                    }
                case .scanning:
                    WorkingView(symbol: Screen.audio.symbol, tint: tint, title: "Scanning",
                                step: "Reading your plugin folders…")
                case .removing:
                    WorkingView(symbol: Screen.audio.symbol, tint: tint, title: "Moving to the Trash",
                                step: "System-wide plugins need your administrator password.")
                case .ready:
                    content
                }
            }
        }
        .animation(.smooth, value: model.phase)
        .sheet(isPresented: Binding(get: { !uninstalling.isEmpty }, set: { if !$0 { uninstalling = [] } })) {
            PluginUninstallSheet(plugins: uninstalling) { bundles, related in
                uninstalling = []
                Task { await remove(bundles: bundles, related: related, source: "Audio plugins") }
            }
        }
    }

    private func remove(bundles: [PluginBundle], related: [PluginRelatedFile], source: String) async {
        let done = await model.remove(bundles: bundles, related: related, using: state.trash)
        if done, let outcome = model.outcome {
            state.recordTrash(outcome, from: source)
        }
    }

    // MARK: Ready

    private var content: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            ResultHeader(bytes: model.totalBytes, caption: "in \(model.plugins.count) plugins",
                         detail: PluginFormat.allCases.map { "\($0.label) \(model.count(of: $0))" }.joined(separator: " · "),
                         tint: tint) {
                HStack(spacing: 10) {
                    Picker("View", selection: $model.tab) {
                        ForEach(AudioModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    Button(action: model.scan) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Scan again")
                }
            }
            Divider()
            switch model.tab {
            case .plugins: pluginList
            case .cleanUp: cleanUp
            }
        }
    }

    // MARK: Plugins

    private var pluginList: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search plugins or vendors", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Picker("Format", selection: $model.formatFilter) {
                    Text("All formats").tag(PluginFormat?.none)
                    ForEach(PluginFormat.allCases) { Text($0.label).tag(PluginFormat?.some($0)) }
                }
                .fixedSize()
                Picker("Sort", selection: $model.sort) {
                    ForEach(AudioModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                Spacer()
                Button("Uninstall\(model.selection.isEmpty ? "" : " \(model.selection.count)")…") {
                    uninstalling = model.selectedPlugins
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(model.selection.isEmpty)
            }
            .controlSize(.regular)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            List {
                Section {
                    ForEach(model.visiblePlugins) { plugin in
                        PluginRow(plugin: plugin, hasUninstaller: model.uninstaller(for: plugin) != nil,
                                  isSelected: selectionBinding(plugin.id)) {
                            uninstalling = [plugin]
                        }
                    }
                } footer: {
                    if model.appleCount > 0 {
                        Text("Apple's \(model.appleCount) built-in plugins are hidden and never removed.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.visiblePlugins.isEmpty {
                    ContentUnavailableView(model.plugins.isEmpty ? "No plugins found" : "No matches",
                                           systemImage: "pianokeys")
                }
            }
        }
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { model.selection.contains(id) },
                set: { if $0 { model.selection.insert(id) } else { model.selection.remove(id) } })
    }

    // MARK: Clean up

    private var cleanUp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cacheCard
                if !model.hasAAXHost && !model.aaxBundles.isEmpty {
                    aaxCard
                }
                if !model.orphanPresets.isEmpty {
                    presetsCard
                }
            }
            .padding(24)
        }
        .alert("Reset plugin caches?", isPresented: $confirmingCaches) {
            Button("Move to Trash", role: .destructive) {
                Task { await remove(bundles: [], related: model.caches, source: "Plugin caches") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.runningHosts.isEmpty
                 ? "Your music apps rescan their plugins the next time they open, which can take a little longer."
                 : "Quit \(model.runningHosts.joined(separator: ", ")) first. Apps rewrite these caches when they quit.")
        }
        .alert("Move \(model.aaxBundles.count) AAX plugins to the Trash?", isPresented: $confirmingAAX) {
            Button("Move to Trash", role: .destructive) {
                Task { await remove(bundles: model.aaxBundles, related: [], source: "AAX plugins") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the AAX versions are removed. Your Audio Unit, VST and VST3 versions stay. You'll be asked for your administrator password.")
        }
    }

    private var cacheCard: some View {
        CleanUpCard(symbol: "arrow.triangle.2.circlepath", tint: tint, title: "Plugin caches",
                    text: "If a plugin doesn't show up or crashes during a scan, resetting the caches makes your apps check every plugin again.") {
            if model.caches.isEmpty {
                Text("No plugin caches found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.caches) { cache in
                    PathRow(path: ReportedPath(path: cache.path, size: ByteSize.format(cache.size)))
                }
                Button("Reset Caches…") { confirmingCaches = true }
                    .padding(.top, 4)
            }
        }
    }

    private var aaxCard: some View {
        let bytes = model.aaxBundles.map(\.size).reduce(0, +)
        return CleanUpCard(symbol: "rectangle.stack.badge.minus", tint: .orange, title: "AAX plugins nothing uses",
                           text: "AAX plugins only run in Avid apps like Pro Tools, and none is installed in Applications. \(model.aaxBundles.count) AAX plugins use \(ByteSize.format(bytes)).") {
            Button("Remove AAX Versions…") { confirmingAAX = true }
        }
    }

    private var presetsCard: some View {
        CleanUpCard(symbol: "slider.horizontal.3", tint: .secondary, title: "Presets for removed plugins",
                    text: "Nothing from these vendors is installed any more. Presets you made yourself are in here too, so check before removing.") {
            ForEach(model.orphanPresets) { folder in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { presetSelection.contains(folder.path) },
                        set: { if $0 { presetSelection.insert(folder.path) } else { presetSelection.remove(folder.path) } }))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    PathRow(path: ReportedPath(path: folder.path, size: ByteSize.format(folder.size)))
                }
            }
            Button("Move Selected to Trash") {
                let chosen = model.orphanPresets.filter { presetSelection.contains($0.path) }
                presetSelection = []
                Task { await remove(bundles: [], related: chosen, source: "Old presets") }
            }
            .disabled(presetSelection.isEmpty)
            .padding(.top, 4)
        }
    }
}

// MARK: - Rows and cards

private struct PluginRow: View {
    let plugin: AudioPlugin
    let hasUninstaller: Bool
    @Binding var isSelected: Bool
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Select \(plugin.name)", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            FileIcon(path: plugin.bundles[0].path, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text([plugin.vendor, plugin.version].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ForEach(plugin.formats) { FormatBadge(format: $0) }
            }
            Text(ByteSize.format(plugin.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
        .contextMenu {
            Button("Uninstall…", action: onUninstall)
            Divider()
            ForEach(plugin.bundles) { bundle in
                Button("Show \(bundle.format.label) in Finder") { Finder.reveal(bundle.path) }
            }
        }
        .help(hasUninstaller ? "The vendor also provides its own uninstaller" : plugin.bundles.map(\.path).joined(separator: "\n"))
    }
}

struct FormatBadge: View {
    let format: PluginFormat

    var body: some View {
        Text(format.label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct CleanUpCard<Content: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.headline)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}

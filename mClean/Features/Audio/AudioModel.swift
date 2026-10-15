import AppKit

/// Audio Plugins: finds AU, VST, VST3, AAX and CLAP plug-ins, uninstalls the
/// ones you pick (to the Trash), and cleans up caches and leftovers.
@Observable
final class AudioModel {
    enum Phase: Equatable {
        case idle, scanning, ready, removing
    }

    enum Tab: String, CaseIterable, Identifiable {
        case plugins = "Plugins", cleanUp = "Clean Up"
        var id: Self { self }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case name = "Name", size = "Size", vendor = "Vendor"
        var id: Self { self }
    }

    private(set) var phase: Phase = .idle
    /// Third-party plug-ins. Apple's are counted but never listed.
    private(set) var plugins: [AudioPlugin] = []
    private(set) var appleCount = 0
    private(set) var caches: [PluginRelatedFile] = []
    private(set) var orphanPresets: [PluginRelatedFile] = []
    private(set) var hasAAXHost = true
    private(set) var uninstallers: [String: String] = [:]
    private(set) var outcome: TrashBin.MoveOutcome?

    var tab: Tab = .plugins
    var sort: Sort = .name
    var formatFilter: PluginFormat?
    var query = ""
    var selection: Set<String> = []

    // MARK: Lists

    var visiblePlugins: [AudioPlugin] {
        let filtered = plugins.filter { plugin in
            (formatFilter.map { plugin.formats.contains($0) } ?? true)
                && (query.isEmpty || plugin.name.localizedCaseInsensitiveContains(query)
                    || plugin.vendor.localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case .name: return filtered
        case .size: return filtered.sorted { $0.size > $1.size }
        case .vendor: return filtered.sorted { ($0.vendor, $0.name) < ($1.vendor, $1.name) }
        }
    }

    var selectedPlugins: [AudioPlugin] { plugins.filter { selection.contains($0.id) } }
    var totalBytes: Int64 { plugins.map(\.size).reduce(0, +) }

    func count(of format: PluginFormat) -> Int {
        plugins.reduce(0) { $0 + $1.bundles.filter { $0.format == format }.count }
    }

    var aaxBundles: [PluginBundle] { plugins.flatMap(\.bundles).filter { $0.format == .aax } }

    /// The vendor's own uninstaller for this plug-in, if one is installed.
    func uninstaller(for plugin: AudioPlugin) -> String? {
        let name = plugin.name.lowercased()
        return uninstallers.first { name.hasPrefix($0.key) || name.contains(" \($0.key)") }?.value
    }

    // MARK: Scanning

    func scan() {
        outcome = nil
        phase = .scanning
        Task { await refresh() }
    }

    private func refresh() async {
        let result = await Task.detached { () -> ScanResult in
            let all = AudioPluginScanner.group(AudioPluginScanner.scanBundles())
            let thirdParty = all.filter { !$0.isApple }
            let orphans = AudioPluginScanner.orphanPresetFolders(
                AudioPluginScanner.presetVendorFolders(), installedVendors: thirdParty.map(\.vendor))
            return ScanResult(
                plugins: thirdParty,
                appleCount: all.count - thirdParty.count,
                caches: AudioPluginScanner.pluginCaches(),
                orphanPresets: orphans.map {
                    PluginRelatedFile(path: $0, kind: .presets, size: AudioPluginScanner.allocatedSize(of: $0))
                },
                hasAAXHost: AudioPluginScanner.hasAAXHost(),
                uninstallers: AudioPluginScanner.vendorUninstallers())
        }.value
        plugins = result.plugins
        appleCount = result.appleCount
        caches = result.caches
        orphanPresets = result.orphanPresets
        hasAAXHost = result.hasAAXHost
        uninstallers = result.uninstallers
        selection = selection.intersection(Set(plugins.map(\.id)))
        phase = .ready
    }

    nonisolated private struct ScanResult: Sendable {
        var plugins: [AudioPlugin]
        var appleCount: Int
        var caches: [PluginRelatedFile]
        var orphanPresets: [PluginRelatedFile]
        var hasAAXHost: Bool
        var uninstallers: [String: String]
    }

    // MARK: Removing

    /// Moves plug-in bundles and related files to the Trash. System-wide items
    /// need an administrator, so macOS asks for a password once for all of them.
    /// Returns false when the password prompt was cancelled.
    @discardableResult
    func remove(bundles: [PluginBundle], related: [PluginRelatedFile], using trash: TrashModel) async -> Bool {
        Notifier.requestPermission()
        let sizes = Dictionary(bundles.map { ($0.path, $0.size) } + related.map { ($0.path, $0.size) },
                               uniquingKeysWith: { first, _ in first })
        let home = NSHomeDirectory() + "/"
        let paths = Array(sizes.keys)
        let personal = paths.filter { $0.hasPrefix(home) }
        let system = paths.filter { !$0.hasPrefix(home) }

        phase = .removing
        // Let the progress screen draw before macOS shows its password prompt.
        try? await Task.sleep(for: .milliseconds(150))

        var result = await trash.move(personal.map { (path: $0, size: sizes[$0] ?? 0) })
        if !system.isEmpty {
            let admin = await AdminTrash.move(system, reason: "mClean needs your password to move audio plug-ins to the Trash.")
            if admin.cancelled && result.movedCount == 0 {
                phase = .ready
                return false
            }
            let movedBytes = admin.moved.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
            trash.didTrash(movedBytes)
            result.movedBytes += movedBytes
            result.movedCount += admin.moved.count
            result.failures += admin.failed.map { ($0 as NSString).lastPathComponent }
        }

        outcome = result
        selection = []
        await refresh()
        Notifier.postIfInBackground("Audio plug-ins moved to the Trash",
                                    "\(ByteSize.format(result.movedBytes)) from \(result.movedCount) items.")
        return true
    }

    func dismissOutcome() {
        outcome = nil
    }

    // MARK: Hosts

    /// Audio apps that keep plug-in caches open and rewrite them when they quit.
    var runningHosts: [String] {
        let hosts = ["com.steinberg.cubase", "com.steinberg.nuendo", "com.steinberg.dorico", "com.apple.logic10",
                     "com.apple.mainstage", "com.cockos.reaper", "com.ableton.live", "com.image-line.flstudio",
                     "com.bitwig.studio", "com.presonus.studioone", "com.avid.protools", "com.apple.garageband10"]
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier?.lowercased(), hosts.contains(where: { id.hasPrefix($0) }) else { return nil }
            return app.localizedName
        }
    }
}

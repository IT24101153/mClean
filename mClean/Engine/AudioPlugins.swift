import Foundation

// MARK: - Model

nonisolated enum PluginFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case au, vst, vst3, aax, clap

    var id: Self { self }

    var label: String {
        switch self {
        case .au: "AU"
        case .vst: "VST"
        case .vst3: "VST3"
        case .aax: "AAX"
        case .clap: "CLAP"
        }
    }

    var fileExtension: String {
        switch self {
        case .au: "component"
        case .vst: "vst"
        case .vst3: "vst3"
        case .aax: "aaxplugin"
        case .clap: "clap"
        }
    }

    init?(fileExtension: String) {
        guard let format = Self.allCases.first(where: { $0.fileExtension == fileExtension.lowercased() }) else { return nil }
        self = format
    }

    /// Where plug-ins of this format are installed, for everyone and for this user.
    var folders: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .au: return ["/Library/Audio/Plug-Ins/Components", "\(home)/Library/Audio/Plug-Ins/Components"]
        case .vst: return ["/Library/Audio/Plug-Ins/VST", "\(home)/Library/Audio/Plug-Ins/VST"]
        case .vst3: return ["/Library/Audio/Plug-Ins/VST3", "\(home)/Library/Audio/Plug-Ins/VST3"]
        case .clap: return ["/Library/Audio/Plug-Ins/CLAP", "\(home)/Library/Audio/Plug-Ins/CLAP"]
        case .aax: return ["/Library/Application Support/Avid/Audio/Plug-Ins",
                           "/Library/Application Support/Avid/Audio/Plug-Ins (Unused)"]
        }
    }
}

/// One plug-in file, such as `FabFilter One.vst3`.
nonisolated struct PluginBundle: Identifiable, Sendable, Hashable {
    var path: String
    var format: PluginFormat
    /// The product name stored in the bundle, which is the same in every
    /// format even when file names aren't (`iZOzone12AUHook` is "Ozone 12").
    var bundleName: String?
    var bundleID: String?
    var vendor: String
    var version: String?
    /// "Vendor: Name" from an Audio Unit, which also names its preset folder.
    var audioUnitName: String?
    var size: Int64

    var id: String { path }
    var fileName: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    var name: String {
        guard let bundleName, bundleName.count > 1, !PluginFormat.allCases.contains(where: { $0.label == bundleName.uppercased() })
        else { return fileName }
        return bundleName
    }
    var isSystemWide: Bool { !path.hasPrefix(NSHomeDirectory() + "/") }
}

/// A plug-in product: every format of it found on this Mac.
nonisolated struct AudioPlugin: Identifiable, Sendable, Hashable {
    var name: String
    var vendor: String
    var bundles: [PluginBundle]

    var id: String { AudioPluginScanner.groupKey(name: name, vendor: vendor) }
    var formats: [PluginFormat] { PluginFormat.allCases.filter { format in bundles.contains { $0.format == format } } }
    var size: Int64 { bundles.map(\.size).reduce(0, +) }
    var version: String? { bundles.compactMap(\.version).max { $0.compare($1, options: .numeric) == .orderedAscending } }
    var needsAdmin: Bool { bundles.contains(where: \.isSystemWide) }
    var isApple: Bool {
        AudioPluginScanner.vendorKey(vendor) == "apple"
            || bundles.contains { $0.bundleID?.lowercased().hasPrefix("com.apple.") == true }
    }
}

/// Something related to a plug-in that can go with it: settings, caches, presets.
nonisolated struct PluginRelatedFile: Identifiable, Sendable, Hashable {
    enum Kind: Sendable { case settings, cache, presets }

    var path: String
    var kind: Kind
    var size: Int64

    var id: String { path }
    var isPersonal: Bool { kind == .presets }
}

// MARK: - Scanning

nonisolated enum AudioPluginScanner {
    /// Finds every plug-in bundle. Slow on large collections, so call it off the main thread.
    static func scanBundles() -> [PluginBundle] {
        var bundles: [PluginBundle] = []
        var seen = Set<String>()
        for format in PluginFormat.allCases {
            for folder in format.folders {
                for path in findBundles(in: folder, withExtension: format.fileExtension) where seen.insert(path).inserted {
                    bundles.append(readBundle(at: path, format: format))
                }
            }
        }
        return resolveVendors(bundles)
    }

    /// Plug-ins sit directly in a format folder or in one level of vendor folders.
    private static func findBundles(in folder: String, withExtension ext: String) -> [String] {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(atPath: folder) else { return [] }
        var found: [String] = []
        for child in children where !child.hasPrefix(".") {
            let path = (folder as NSString).appendingPathComponent(child)
            if (child as NSString).pathExtension.lowercased() == ext {
                found.append(path)
                continue
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                  (try? fileManager.destinationOfSymbolicLink(atPath: path)) == nil,
                  let nested = try? fileManager.contentsOfDirectory(atPath: path)
            else { continue }
            for item in nested where (item as NSString).pathExtension.lowercased() == ext {
                found.append((path as NSString).appendingPathComponent(item))
            }
        }
        return found
    }

    private static func readBundle(at path: String, format: PluginFormat) -> PluginBundle {
        let info = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let components = info["AudioComponents"] as? [[String: Any]]
        let auName = components?.first?["name"] as? String
        let copyright = (info["NSHumanReadableCopyright"] as? String) ?? (info["CFBundleGetInfoString"] as? String)
        let vendor = vendor(audioUnitName: auName, copyright: copyright) ?? ""
        let version = (info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String)?
            .replacingOccurrences(of: " ", with: "")
        return PluginBundle(path: path, format: format,
                            bundleName: (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespaces),
                            bundleID: info["CFBundleIdentifier"] as? String,
                            vendor: vendor, version: version, audioUnitName: auName, size: allocatedSize(of: path))
    }

    /// Gives every bundle of the same maker the same vendor name. Audio Units
    /// name their maker explicitly ("iZotope: Ozone 12 EQ") while VST3 and AAX
    /// copyright lines can name a parent company, so bundles are linked through
    /// their bundle ID (`com.izotope…`) and the Audio Unit name wins.
    static func resolveVendors(_ bundles: [PluginBundle]) -> [PluginBundle] {
        var byWord: [String: String] = [:]
        for bundle in bundles.sorted(by: { ($0.audioUnitName != nil ? 0 : 1) < ($1.audioUnitName != nil ? 0 : 1) })
        where !bundle.vendor.isEmpty {
            if let word = bundle.bundleID.flatMap(vendorWord(fromBundleID:)), byWord[word] == nil {
                byWord[word] = bundle.vendor
            }
        }
        var byKey: [String: String] = [:]
        for vendor in byWord.values where byKey[vendorKey(vendor)] == nil {
            byKey[vendorKey(vendor)] = vendor
        }

        return bundles.map { bundle in
            var resolved = bundle
            let word = bundle.bundleID.flatMap(vendorWord(fromBundleID:))
            if let word, let vendor = byWord[word] {
                resolved.vendor = vendor
            } else if resolved.vendor.isEmpty {
                let match = word.flatMap { word in
                    byKey.first { key, _ in key.count >= 4 && (word.hasPrefix(key) || key.hasPrefix(word)) }?.value
                }
                resolved.vendor = match ?? word.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Unknown vendor"
            }
            return resolved
        }
    }

    /// Groups every format of the same product into one plug-in. Products are
    /// matched by name; two makers' plug-ins with the same name stay apart.
    static func group(_ bundles: [PluginBundle]) -> [AudioPlugin] {
        var byName: [String: [PluginBundle]] = [:]
        for bundle in bundles {
            byName[nameKey(productName(bundle.name)), default: []].append(bundle)
        }
        var plugins: [AudioPlugin] = []
        for members in byName.values {
            let vendors = Set(members.map { vendorKey($0.vendor) })
            let formatClash = Dictionary(grouping: members, by: \.format).values.contains { $0.count > 1 }
            if vendors.count > 1 && formatClash {
                for sameVendor in Dictionary(grouping: members, by: { vendorKey($0.vendor) }).values {
                    plugins.append(makePlugin(sameVendor))
                }
            } else {
                plugins.append(makePlugin(members))
            }
        }
        return plugins.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func makePlugin(_ bundles: [PluginBundle]) -> AudioPlugin {
        let lead = bundles.first { $0.audioUnitName != nil } ?? bundles[0]
        return AudioPlugin(name: productName(lead.name), vendor: lead.vendor, bundles: bundles)
    }

    // MARK: Names

    /// The vendor part of "FabFilter: Pro-Q 3", or the holder in a copyright line.
    static func vendor(audioUnitName: String?, copyright: String?) -> String? {
        if let audioUnitName, let colon = audioUnitName.firstIndex(of: ":") {
            let vendor = audioUnitName[..<colon].trimmingCharacters(in: .whitespaces)
            if !vendor.isEmpty { return vendor }
        }
        guard let copyright else { return nil }
        var text = copyright
        for marker in ["©", "(c)", "(C)", "Copyright", "copyright", "COPYRIGHT"] {
            if let range = text.range(of: marker, options: .backwards) {
                text = String(text[range.upperBound...])
            }
        }
        text = text.replacingOccurrences(of: "All rights reserved", with: "", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "\\b(19|20)\\d{2}\\b", with: "", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-–()").union(.whitespaces))
        return trimmed.count >= 2 ? trimmed : nil
    }

    /// "jp.co.yamaha.AAX.Compressor" → "yamaha"
    static func vendorWord(fromBundleID bundleID: String) -> String? {
        let generic: Set = ["com", "net", "org", "io", "co", "jp", "de", "fr", "uk", "nl", "se", "it", "us", "ca", "au", "ch"]
        // JUCE's template IDs don't identify anyone.
        let placeholders: Set = ["yourcompany", "mycompany", "juce", "company", "manufacturer"]
        guard let word = bundleID.lowercased().split(separator: ".").map(String.init).first(where: { !generic.contains($0) }),
              !placeholders.contains(word)
        else { return nil }
        return word
    }

    /// The first word of a vendor name, which survives "Inc."/"LLC" differences between formats.
    static func vendorKey(_ vendor: String) -> String {
        let word = vendor.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? ""
        return word.lowercased()
    }

    /// "Archetype Nolly X (VST3)" → "Archetype Nolly X"
    static func productName(_ name: String) -> String {
        name.replacingOccurrences(of: "[ _-]*\\(?(AU|VST3?|AAX|CLAP|x64|64-?bit)\\)?$", with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    static func nameKey(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func groupKey(name: String, vendor: String) -> String {
        "\(vendorKey(vendor))|\(nameKey(name))"
    }

    // MARK: Related files

    /// Settings, caches and presets that belong to these plug-ins and exist.
    static func relatedFiles(for plugin: AudioPlugin) -> [PluginRelatedFile] {
        let home = NSHomeDirectory()
        var candidates: [(String, PluginRelatedFile.Kind)] = []
        for bundleID in Set(plugin.bundles.compactMap(\.bundleID)) {
            candidates.append(("\(home)/Library/Preferences/\(bundleID).plist", .settings))
            candidates.append(("\(home)/Library/Caches/\(bundleID)", .cache))
        }
        for auName in Set(plugin.bundles.compactMap(\.audioUnitName)) {
            guard let presets = presetFolder(forAudioUnitName: auName) else { continue }
            candidates.append(("\(home)/Library/Audio/Presets/\(presets)", .presets))
            candidates.append(("/Library/Audio/Presets/\(presets)", .presets))
        }
        return candidates.compactMap { path, kind in
            FileManager.default.fileExists(atPath: path)
                ? PluginRelatedFile(path: path, kind: kind, size: allocatedSize(of: path)) : nil
        }
    }

    /// "FabFilter: Pro-Q 3" → "FabFilter/Pro-Q 3", the Audio Unit preset folder.
    static func presetFolder(forAudioUnitName name: String) -> String? {
        let parts = name.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !parts[0].contains("/"), !parts[1].contains("/"), parts[1] != "..", parts[0] != ".."
        else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    // MARK: Clean up

    /// Vendor preset folders (`…/Audio/Presets/Vendor`) when nothing from that
    /// vendor is installed any more. Individual plug-in folders aren't judged:
    /// vendors name them in their own ways ("Serum 2 Presets"). Apple's and
    /// Logic's folders belong to built-in plug-ins and are never offered.
    static func orphanPresetFolders(_ vendorFolders: [String], installedVendors: [String]) -> [String] {
        let installed = Set(installedVendors.map(vendorKey))
        return vendorFolders.filter { path in
            let key = vendorKey((path as NSString).lastPathComponent)
            return !key.isEmpty && !["apple", "logic"].contains(key) && !installed.contains(key)
        }
    }

    static func presetVendorFolders() -> [String] {
        let fileManager = FileManager.default
        var folders: [String] = []
        for root in ["\(NSHomeDirectory())/Library/Audio/Presets", "/Library/Audio/Presets"] {
            for vendor in (try? fileManager.contentsOfDirectory(atPath: root)) ?? [] where !vendor.hasPrefix(".") {
                var isDirectory: ObjCBool = false
                let path = (root as NSString).appendingPathComponent(vendor)
                if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    folders.append(path)
                }
            }
        }
        return folders
    }

    /// Plug-in scan caches that apps rebuild on their next launch.
    static func pluginCaches() -> [PluginRelatedFile] {
        let home = NSHomeDirectory()
        let fileManager = FileManager.default
        var paths = ["\(home)/Library/Caches/AudioUnitCache"]

        // Steinberg (Cubase, Nuendo, Dorico): the VST scan caches, never PluginManager.xml.
        let preferences = "\(home)/Library/Preferences"
        for folder in (try? fileManager.contentsOfDirectory(atPath: preferences)) ?? []
        where ["Cubase", "Nuendo", "Dorico"].contains(where: { folder.hasPrefix($0 + " ") }) {
            let base = "\(preferences)/\(folder)"
            for item in (try? fileManager.contentsOfDirectory(atPath: base)) ?? []
            where item.contains("VST3 Cache") || item.hasPrefix("VstPlugInfo") || item.hasSuffix("Module Cache.xml") {
                paths.append("\(base)/\(item)")
            }
        }

        // REAPER: its plug-in scan lists.
        let reaper = "\(home)/Library/Application Support/REAPER"
        for item in (try? fileManager.contentsOfDirectory(atPath: reaper)) ?? []
        where item.hasPrefix("reaper-vstplugins") || item.hasPrefix("reaper-auplugins") || item.hasPrefix("reaper-clap") {
            paths.append("\(reaper)/\(item)")
        }

        return paths.compactMap { path in
            fileManager.fileExists(atPath: path) ? PluginRelatedFile(path: path, kind: .cache, size: allocatedSize(of: path)) : nil
        }
    }

    /// AAX plug-ins only run inside Avid apps such as Pro Tools.
    static func hasAAXHost() -> Bool {
        let fileManager = FileManager.default
        let hosts = ["Pro Tools", "Media Composer"]
        for root in ["/Applications", "\(NSHomeDirectory())/Applications"] {
            let items = (try? fileManager.contentsOfDirectory(atPath: root)) ?? []
            for item in items {
                if hosts.contains(where: { item.hasPrefix($0) }) { return true }
                let nested = (try? fileManager.contentsOfDirectory(atPath: (root as NSString).appendingPathComponent(item))) ?? []
                if item.hasPrefix("Avid") || item.hasPrefix("Pro Tools"),
                   nested.contains(where: { name in hosts.contains { name.hasPrefix($0) } }) {
                    return true
                }
            }
        }
        return false
    }

    /// Vendor uninstallers ("Uninstall Ozone 12.app") keyed by what they uninstall.
    static func vendorUninstallers() -> [String: String] {
        let fileManager = FileManager.default
        var found: [String: String] = [:]
        func visit(_ folder: String, depth: Int) {
            for item in (try? fileManager.contentsOfDirectory(atPath: folder)) ?? [] where !item.hasPrefix(".") {
                let path = (folder as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    let name = (item as NSString).deletingPathExtension
                    if let target = uninstallerTarget(name) { found[target.lowercased()] = path }
                } else if depth < 3 {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                        visit(path, depth: depth + 1)
                    }
                }
            }
        }
        visit("/Applications", depth: 1)
        return found
    }

    /// "Uninstall Ozone 12" → "Ozone 12"; "Arturia Uninstaller" → "Arturia"
    static func uninstallerTarget(_ appName: String) -> String? {
        if appName.hasPrefix("Uninstall ") {
            return String(appName.dropFirst("Uninstall ".count)).trimmingCharacters(in: .whitespaces)
        }
        if appName.hasSuffix(" Uninstaller") {
            return String(appName.dropLast(" Uninstaller".count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: Sizes

    static func allocatedSize(of path: String) -> Int64 {
        let url = URL(filePath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

import Foundation
import Testing

private func bundle(_ file: String, _ format: PluginFormat, name: String? = nil, id: String?, vendor: String = "",
                    auName: String? = nil, version: String? = nil) -> PluginBundle {
    PluginBundle(path: "/Library/Audio/Plug-Ins/\(format.label)/\(file).\(format.fileExtension)", format: format,
                 bundleName: name, bundleID: id, vendor: vendor, version: version, audioUnitName: auName, size: 100)
}

@Suite("Audio plugin vendors")
struct PluginVendorTests {
    @Test("Reads the maker", arguments: [
        ("FabFilter: Pro-Q 3", nil, "FabFilter"),
        ("Valhalla DSP, LLC: ValhallaDelay", nil, "Valhalla DSP, LLC"),
        (nil, "Copyright © 2002-2026 FabFilter", "FabFilter"),
        (nil, "Compressor, Copyright (c) 2026 Yamaha Corporation. All rights reserved.", "Yamaha Corporation"),
        (nil, "FabFilter One 3.52, Copyright © 2002-2026 FabFilter", "FabFilter"),
    ] as [(String?, String?, String)])
    func readsVendor(auName: String?, copyright: String?, expected: String) {
        #expect(AudioPluginScanner.vendor(audioUnitName: auName, copyright: copyright) == expected)
    }

    @Test func ignoresPlaceholderCopyright() {
        #expect(AudioPluginScanner.vendor(audioUnitName: nil, copyright: "COPYRIGHT") == nil)
        #expect(AudioPluginScanner.vendor(audioUnitName: nil, copyright: " ") == nil)
    }

    @Test func readsBundleIDs() {
        #expect(AudioPluginScanner.vendorWord(fromBundleID: "jp.co.yamaha.AAX.Compressor") == "yamaha")
        #expect(AudioPluginScanner.vendorWord(fromBundleID: "com.fabfilter.One.Vst3.3") == "fabfilter")
        #expect(AudioPluginScanner.vendorWord(fromBundleID: "com.yourcompany.MyPlugin") == nil)
    }

    @Test func linksFormatsThroughBundleID() {
        // iZotope's VST3 names its parent company; its Audio Unit names iZotope.
        let resolved = AudioPluginScanner.resolveVendors([
            bundle("iZOzone12AUHook", .au, name: "Ozone 12", id: "com.izotope.AU.OZONE12", vendor: "iZotope", auName: "iZotope: Ozone 12"),
            bundle("Ozone 12", .vst3, name: "Ozone 12", id: "com.izotope.Ozone12.vst3", vendor: "Native Instruments USA, Inc"),
            bundle("ValhallaRoom", .vst, name: "ValhallaRoom", id: "com.valhalladsp.ValhallaRoom"),
            bundle("ValhallaRoom", .au, name: "ValhallaRoom", id: "com.valhalladsp.ValhallaRoomAU",
                   vendor: "Valhalla DSP, LLC", auName: "Valhalla DSP, LLC: ValhallaRoom"),
        ])
        #expect(resolved.map(\.vendor) == ["iZotope", "iZotope", "Valhalla DSP, LLC", "Valhalla DSP, LLC"])
    }
}

@Suite("Audio plugin grouping")
struct PluginGroupingTests {
    @Test func groupsFormatsByStoredName() {
        // iZotope's files are named differently per format; the stored name isn't.
        let plugins = AudioPluginScanner.group([
            bundle("iZOzone12AUHook", .au, name: "Ozone 12", id: "a", vendor: "iZotope"),
            bundle("iZOzone12AAXHook", .aax, name: "Ozone 12", id: "b", vendor: "iZotope"),
            bundle("Ozone 12", .vst3, name: "Ozone 12", id: "c", vendor: "iZotope"),
            bundle("Ozone 12 Bass Control", .vst3, name: "Ozone 12 Bass Control", id: "d", vendor: "iZotope"),
        ])
        #expect(plugins.map(\.name) == ["Ozone 12", "Ozone 12 Bass Control"])
        #expect(plugins.first?.formats == [.au, .vst3, .aax])
    }

    @Test func keepsDifferentMakersApart() {
        let plugins = AudioPluginScanner.group([
            bundle("Compressor", .aax, name: "Compressor", id: "jp.co.yamaha.Compressor", vendor: "Yamaha Corporation"),
            bundle("Compressor", .aax, name: "Compressor", id: "com.other.Compressor", vendor: "Other Audio"),
        ])
        #expect(plugins.count == 2)
    }

    @Test func fallsBackToFileNames() {
        let plain = bundle("FabFilter Saturn (Mono)", .vst, id: "x", vendor: "FabFilter")
        #expect(plain.name == "FabFilter Saturn (Mono)")
        #expect(AudioPluginScanner.productName("Archetype Nolly X (VST3)") == "Archetype Nolly X")
        #expect(AudioPluginScanner.productName("Serum AU") == "Serum")
    }

    @Test func recognizesApplePlugins() {
        let apple = AudioPlugin(name: "AUGraphicEQ", vendor: "Apple", bundles: [bundle("AUGraphicEQ", .au, id: "com.apple.audio.eq")])
        let other = AudioPlugin(name: "Pro-Q 3", vendor: "FabFilter", bundles: [bundle("Pro-Q 3", .au, id: "com.fabfilter.ProQ3")])
        #expect(apple.isApple)
        #expect(!other.isApple)
    }
}

@Suite("Audio plugin cleanup")
struct PluginCleanupTests {
    @Test func findsPresetFolders() {
        #expect(AudioPluginScanner.presetFolder(forAudioUnitName: "FabFilter: Pro-Q 3") == "FabFilter/Pro-Q 3")
        #expect(AudioPluginScanner.presetFolder(forAudioUnitName: "No colon") == nil)
        #expect(AudioPluginScanner.presetFolder(forAudioUnitName: "Evil: ../..") == nil)
    }

    @Test func offersOnlyVendorsWithNothingInstalled() {
        let folders = ["/Users/me/Library/Audio/Presets/Xfer Records", "/Users/me/Library/Audio/Presets/Apple",
                       "/Library/Audio/Presets/Logic", "/Library/Audio/Presets/OldSynth Co",
                       "/Library/Audio/Presets/Valhalla DSP, LLC"]
        let orphans = AudioPluginScanner.orphanPresetFolders(folders, installedVendors: ["Xfer Records", "Valhalla DSP, LLC"])
        #expect(orphans == ["/Library/Audio/Presets/OldSynth Co"])
    }

    @Test func readsVendorUninstallers() {
        #expect(AudioPluginScanner.uninstallerTarget("Uninstall Ozone 12") == "Ozone 12")
        #expect(AudioPluginScanner.uninstallerTarget("Arturia Uninstaller") == "Arturia")
        #expect(AudioPluginScanner.uninstallerTarget("Ozone 12") == nil)
    }

    @Test func mapsFormatsToFolders() {
        #expect(PluginFormat(fileExtension: "VST3") == .vst3)
        #expect(PluginFormat(fileExtension: "aaxplugin") == .aax)
        #expect(PluginFormat.aax.folders.first == "/Library/Application Support/Avid/Audio/Plug-Ins")
    }
}

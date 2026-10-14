import Foundation
import Testing

/// The fixtures are real Mole 1.59.1 output captured on a Mac, with personal
/// details replaced. If a Mole update changes its wording, these fail before
/// a screen quietly shows nothing.
private final class FixtureBundle {}

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: nil),
                           "Missing fixture \(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

private func report(_ name: String) throws -> MoleReport {
    var report = MoleReport()
    for line in try fixture(name).components(separatedBy: "\n") {
        report.consume(line)
    }
    return report
}

private func decode<T: Decodable>(_ type: T.Type, _ name: String, snakeCase: Bool = false) throws -> T {
    let decoder = JSONDecoder()
    if snakeCase { decoder.keyDecodingStrategy = .convertFromSnakeCase }
    return try decoder.decode(T.self, from: Data(fixture(name).utf8))
}

@Suite("Sizes")
struct SizeTests {
    @Test("Mole's decimal sizes", arguments: [
        ("118.4MB", 118_400_000), ("468KB", 468_000), ("3.27GB", 3_270_000_000), ("0B", 0),
        ("10 items, 92.5MB", 92_500_000), ("1.5TB", 1_500_000_000_000),
    ] as [(String, Int64)])
    func parsesSizes(text: String, bytes: Int64) {
        #expect(ByteSize.parse(text) == bytes)
    }

    @Test func ignoresTextWithoutSize() {
        #expect(ByteSize.parse("would clean") == nil)
    }
}

@Suite("System Junk preview")
struct CleanPreviewTests {
    @Test func readsSummary() throws {
        let preview = try report("clean-preview.txt")
        #expect(preview.summaryTitle == "Dry run complete - no changes made")
        #expect(preview.summaryValue("Potential space") == "548.6MB")
        #expect(preview.summaryValue("Items") == "153")
        #expect(preview.summaryValue("Categories") == "5")
    }

    @Test func groupsItemsIntoSections() throws {
        let preview = try report("clean-preview.txt")
        let cleanable = preview.sections.filter { section in
            section.meaningfulItems.contains { $0.state == .preview }
        }
        #expect(cleanable.map { $0.title } == ["User essentials", "App caches", "Developer tools",
                                           "Apps & utilities", "Application Support"])

        let first = try #require(preview.sections.first?.items.first)
        #expect(first.title == "User app cache")
        #expect(first.detail == "10 items, 92.5MB")
        #expect(first.bytes == 92_500_000)
    }

    @Test func flagsEmptySections() throws {
        let preview = try report("clean-preview.txt")
        let virtualization = try #require(preview.sections.first { $0.title == "Virtualization" })
        #expect(virtualization.meaningfulItems.isEmpty)
        #expect(virtualization.items.allSatisfy { $0.isPlaceholder })
    }

    @Test func findsFullDiskAccessWarning() throws {
        let trash = try #require(try report("clean-preview.txt").allItems.first { $0.title == "Trash" })
        #expect(trash.state == .warning)
        #expect(trash.detail?.contains("Full Disk Access") == true)
        #expect(MoleText.friendly(trash.detail ?? "").hasSuffix("to mClean"))
    }

    @Test func keepsReviewOnlyItemsSeparate() throws {
        let review = try report("clean-preview.txt").allItems.filter { $0.state == .review }
        #expect(review.map { $0.title } == ["Simulator data", "NuGet packages", "Build artifacts"])
        #expect(review.first?.bytes == 3_270_000_000)
        #expect(review.first?.mentionedPath?.hasSuffix("/Library/Developer/CoreSimulator/Devices") == true)
        #expect(review.last?.mentionedPath == nil)
    }

    @Test func hidesCommandLineHintsFromSummary() throws {
        let details = try report("clean-preview.txt").summaryDetails
        #expect(!details.contains { $0.contains("mo clean") || $0.hasPrefix("Detailed file list") })
    }

    @Test func readsCleanList() throws {
        let groups = CleanList.parse(try fixture("clean-list.txt"))
        #expect(groups.keys.sorted() == ["App caches", "Application Support", "Apps & utilities",
                                         "Developer tools", "User essentials"])
        #expect(groups.values.map { $0.count }.reduce(0, +) == 160)
        #expect(groups["User essentials"]?.allSatisfy { $0.path.hasPrefix("/") && $0.size != nil } == true)
    }
}

@Suite("Optimize preview")
struct OptimizePreviewTests {
    @Test func readsTasksAndOutcomes() throws {
        let preview = try report("optimize-preview.txt")
        #expect(preview.sections.count == 20)
        #expect(preview.summary.contains("Would apply 2 optimizations"))
        #expect(preview.summary.contains("13 unchanged | 2 skipped | 2 unavailable | 1 failed"))
    }

    @Test("Labels follow Mole's wording", arguments: [
        ("Finder Cache Refresh", "willRun"),
        ("Broken Config Repair", "healthy"),
        ("Network Stack Refresh", "attention"),
        ("Periodic Maintenance", "unavailable"),
        ("Shared File Lists", "unavailable"),
        ("Disk Health", "skipped"),
    ])
    func labelsTasks(title: String, expected: String) throws {
        let task = try #require(try report("optimize-preview.txt").sections.first { $0.title == title })
        #expect(String(describing: TaskStatus(task)) == expected)
    }
}

@Suite("Developer Junk preview")
struct PurgePreviewTests {
    @Test func readsArtifacts() throws {
        let preview = try report("purge-preview.txt")
        let artifacts = PurgeOutput.artifacts(in: preview)
        #expect(artifacts.count == 12)
        #expect(artifacts.first?.path == "~/Development/Android/ShopApp/app/build")
        #expect(artifacts.first?.size == "351.3MB")
        #expect(preview.summaryValue("Would free approximately") == "1.22GB")
    }

    @Test func tellsDependenciesFromBuildOutput() {
        #expect(ArtifactKind(path: ReportedPath(path: "~/web/node_modules")) == .dependencies)
        #expect(ArtifactKind(path: ReportedPath(path: "~/ios/Pods")) == .dependencies)
        #expect(ArtifactKind(path: ReportedPath(path: "~/android/app/build")) == .build)
    }
}

@Suite("Uninstall preview")
struct UninstallPreviewTests {
    @Test func readsRemovalPlan() throws {
        let plan = UninstallPlan.parse(try fixture("uninstall-preview.txt"))
        #expect(plan.appTitle == "Mac Mouse Fix")
        #expect(plan.totalSize == "20.4MB")
        #expect(plan.matchedApps == 1)
        #expect(plan.files.count == 6)
        #expect(plan.files.first?.path == "/Applications/Mac Mouse Fix.app")
        #expect(plan.systemFiles.isEmpty)
        #expect(!plan.isEmpty)
    }

    @Test func stripsTerminalCodes() {
        #expect(MoleText.clean("\u{1B}[2J\u{1B}[H◎ Matched 1 app(s):\r") == "◎ Matched 1 app(s):")
    }
}

@Suite("JSON output")
struct JSONOutputTests {
    @Test func decodesStatus() throws {
        let status = try decode(StatusSnapshot.self, "status.json", snakeCase: true)
        #expect(status.healthScore == 100)
        #expect(status.startupDisk?.mount == "/")
        #expect(status.hardware?.model == "MacBook Air")
        #expect((status.memory?.total ?? 0) > 0)
    }

    @Test func decodesInstalledApps() throws {
        let apps = try decode([InstalledApp].self, "apps.json")
        #expect(apps.count == 8)
        #expect(apps.allSatisfy { $0.path.hasSuffix(".app") && !$0.uninstallName.isEmpty })
        #expect(apps.first?.bytes == 199_900_000)
    }

    @Test func decodesDiskOverview() throws {
        let scan = try decode(DiskScan.self, "analyze-overview.json")
        #expect(scan.overview == true)
        #expect(scan.entries?.contains { $0.name == "Home" && $0.isDirectory } == true)
        #expect(scan.entries?.contains { $0.insight == true && $0.name == "Xcode Simulators" } == true)
    }

    @Test func hidesPreviewsFromHistory() throws {
        let history = try decode(CleanupHistory.self, "history.json", snakeCase: true)
        #expect(history.sessions.count == 5)
        // All five are previews or app listings, including an optimize preview
        // whose failed task makes it look like a real run.
        #expect(history.sessions.allSatisfy { !$0.changedSomething })
    }

    @Test func keepsRealRunsInHistory() throws {
        let json = #"{"sessions": [{"command": "clean", "items": 88, "size": "850.4MB", "operation_count": 206, "actions": {"removed": 88, "trashed": 0, "skipped": 116, "failed": 2, "rebuilt": 0, "other": 0}}]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let history = try decoder.decode(CleanupHistory.self, from: Data(json.utf8))
        #expect(history.sessions.first?.changedSomething == true)
    }
}

@Suite("Installers")
struct InstallerTests {
    @Test func recognizesInstallerFiles() {
        #expect(InstallerScanner.candidate(forFileNamed: "Xcode.xip") == .installer)
        #expect(InstallerScanner.candidate(forFileNamed: "Setup.PKG") == .installer)
        #expect(InstallerScanner.candidate(forFileNamed: "App.dmg") == .installer)
        #expect(InstallerScanner.candidate(forFileNamed: "Photos.zip") == .zipToInspect)
        #expect(InstallerScanner.candidate(forFileNamed: "notes.txt") == .none)
    }

    @Test func checksWhatAZipHolds() {
        #expect(InstallerScanner.zipListingHoldsInstaller("MyApp.app/\nMyApp.app/Contents/Info.plist"))
        #expect(InstallerScanner.zipListingHoldsInstaller("readme.txt\nTool.pkg"))
        #expect(!InstallerScanner.zipListingHoldsInstaller("photos/a.jpg\nphotos/b.jpg"))
        #expect(!InstallerScanner.zipListingHoldsInstaller("notes/app.application.txt"))
    }

    @Test func onlyLooksAtTheFirstFiftyEntries() {
        let listing = (1...50).map { "file\($0).txt" }.joined(separator: "\n") + "\nLate.app/"
        #expect(!InstallerScanner.zipListingHoldsInstaller(listing))
    }
}

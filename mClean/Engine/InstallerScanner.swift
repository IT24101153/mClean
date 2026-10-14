import Foundation

/// A downloaded installer that is usually safe to delete once the app is installed.
nonisolated struct InstallerFile: Identifiable, Sendable, Hashable {
    var path: String
    var size: Int64
    var modified: Date?

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var kind: String { (path as NSString).pathExtension.uppercased() }

    /// "Downloads", "Desktop", …: the scanned folder the file lives under.
    var location: String {
        let home = NSHomeDirectory()
        for folder in InstallerScanner.folders where path.hasPrefix(folder + "/") {
            return folder.hasPrefix(home + "/")
                ? String(folder.dropFirst(home.count + 1))
                : folder
        }
        return (path as NSString).deletingLastPathComponent
    }
}

/// Finds installer files with the same rules as `mole installer`, which can
/// only be driven from a terminal: the same folders, two levels deep, disk
/// images and packages, and ZIP files that hold an app or installer.
nonisolated enum InstallerScanner {
    static var folders: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Downloads",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Public",
            "\(home)/Library/Downloads",
            "/Users/Shared",
            "\(home)/Library/Caches/Homebrew",
            "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Downloads",
            "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            "\(home)/Library/Application Support/Telegram Desktop",
        ]
    }

    static let maxDepth = 2
    static let installerExtensions: Set = ["dmg", "pkg", "mpkg", "iso", "xip"]
    private static let zipEntriesChecked = 50
    private static let zipInstallerEntry = try! NSRegularExpression(pattern: "\\.(app|pkg|dmg|xip)(/|$)")

    enum Candidate {
        case installer, zipToInspect, none
    }

    static func candidate(forFileNamed name: String) -> Candidate {
        let ext = (name as NSString).pathExtension.lowercased()
        if installerExtensions.contains(ext) { return .installer }
        return ext == "zip" ? .zipToInspect : .none
    }

    /// A ZIP counts when one of its first 50 entries is an app or installer.
    static func zipListingHoldsInstaller(_ listing: String) -> Bool {
        listing.split(separator: "\n").prefix(zipEntriesChecked).contains { entry in
            let text = String(entry)
            return zipInstallerEntry.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    /// Walks the folders. Slow on large Downloads folders, so call it off the main thread.
    static func scan() -> [InstallerFile] {
        var found: [String: InstallerFile] = [:]
        for folder in folders {
            for file in scan(folder) where found[file.path] == nil {
                found[file.path] = file
            }
        }
        return found.values.sorted { $0.size > $1.size }
    }

    private static func scan(_ folder: String) -> [InstallerFile] {
        let root = URL(filePath: folder)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true })
        else { return [] }

        var files: [InstallerFile] = []
        let rootDepth = root.pathComponents.count
        for case let url as URL in walker {
            if url.pathComponents.count - rootDepth >= maxDepth {
                walker.skipDescendants()
            }
            guard url.pathComponents.count - rootDepth <= maxDepth,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true
            else { continue }

            switch candidate(forFileNamed: url.lastPathComponent) {
            case .installer:
                break
            case .zipToInspect:
                guard let listing = zipListing(url.path), zipListingHoldsInstaller(listing) else { continue }
            case .none:
                continue
            }
            files.append(InstallerFile(path: url.path, size: Int64(values.fileSize ?? 0),
                                       modified: values.contentModificationDate))
        }
        return files
    }

    /// `zipinfo -1`, given a few seconds. Unreadable or slow archives are skipped.
    private static func zipListing(_ path: String) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zipinfo")
        process.arguments = ["-1", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Read while it runs so a long listing can't fill the pipe and stall.
        let output = ListingBuffer()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: output.data, as: UTF8.self)
    }
}

nonisolated private final class ListingBuffer: @unchecked Sendable {
    var data = Data()
}

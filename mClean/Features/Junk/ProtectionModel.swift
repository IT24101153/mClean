import Foundation

/// What System Junk must never clean, stored in Mole's own protection list
/// (`~/.config/mole/whitelist`) through Mole's functions.
@Observable
final class ProtectionModel {
    struct Item: Identifiable, Hashable {
        let name: String
        let pattern: String
        let category: String
        var isProtected: Bool

        var id: String { pattern }
    }

    private(set) var items: [Item] = []
    /// Protected paths without a named item, including Mole's own extra defaults.
    private(set) var customPatterns: [String] = []
    private(set) var isLoading = false
    private(set) var error: String?
    /// Paths protected from the System Junk list since the last scan.
    private(set) var recentlyProtected: Set<String> = []

    private static let helper = "mclean-protect"

    func load(with engine: MoleEngine) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let run = try await engine.helper(Self.helper, ["state"])
            guard run.succeeded else { throw MoleError.failed(run.failureMessage) }
            (items, customPatterns) = Self.parse(run.output)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Saves the complete list. Writing the file replaces Mole's optional
    /// defaults, so the custom patterns (which hold those defaults) always go along.
    func save(items: [Item], customPatterns: [String], with engine: MoleEngine) async throws {
        let home = NSHomeDirectory()
        let named = items.filter(\.isProtected).map { item in
            item.pattern.hasPrefix(home + "/") ? "~" + item.pattern.dropFirst(home.count) : item.pattern
        }
        let input = (named + customPatterns).joined(separator: "\n") + "\n"
        let run = try await engine.helper(Self.helper, ["save"], input: input, purpose: .change)
        guard run.succeeded else { throw MoleError.failed(run.failureMessage) }
        await load(with: engine)
    }

    /// Adds one exact path from the System Junk review list.
    func protect(_ path: String, with engine: MoleEngine) async throws {
        if items.isEmpty { await load(with: engine) }
        guard error == nil else { throw MoleError.failed(error ?? "") }
        var custom = customPatterns
        if !custom.contains(path) { custom.append(path) }
        try await save(items: items, customPatterns: custom, with: engine)
        recentlyProtected.insert(path)
    }

    func scanned() {
        recentlyProtected = []
    }

    static func parse(_ output: String) -> (items: [Item], custom: [String]) {
        var items: [Item] = []
        var custom: [String] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.first == "item", fields.count >= 5 {
                items.append(Item(name: fields[2], pattern: fields[3], category: fields[4], isProtected: fields[1] == "1"))
            } else if fields.first == "custom", fields.count >= 2 {
                custom.append(fields[1])
            }
        }
        return (items, custom)
    }

    static func categoryTitle(_ category: String) -> String {
        switch category {
        case "browser_cache": "Browsers"
        case "ide_cache": "Developer tools"
        case "package_manager": "Package managers"
        case "compiler_cache": "Build caches"
        case "ai_ml_cache": "AI and models"
        case "container_cache": "Containers"
        case "network_tools": "Network tools"
        case "app_cache": "Apps"
        case "system_cache": "System"
        default: category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

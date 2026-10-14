#if DEBUG
import AppKit

/// Debug builds only: walks through screens and saves the window as PNGs.
///
///     MCLEAN_SNAPSHOT_DIR=/tmp/shots \
///     MCLEAN_SNAPSHOT_SCRIPT="overview:6,junk-scan:40,apps:15" \
///     open mClean.app
///
/// Each step is `screen[-action]:seconds`. Actions only run previews
/// (dry-runs); nothing is ever deleted.
enum DebugSnapshots {
    static func runIfRequested(_ state: AppState) async {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["MCLEAN_SNAPSHOT_DIR"], let script = env["MCLEAN_SNAPSHOT_SCRIPT"] else { return }

        switch env["MCLEAN_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // Registered, not saved: the real welcome screen still shows on a normal launch.
        UserDefaults.standard.register(defaults: ["didShowWelcome": true])

        let run = UUID().uuidString.prefix(4)
        log("runner \(run) start state=\(ObjectIdentifier(state).hashValue)", directory)
        try? await Task.sleep(for: .seconds(2))
        for step in script.split(separator: ",") {
            let parts = step.split(separator: ":")
            let name = String(parts[0])
            let seconds = parts.count > 1 ? Double(parts[1]) ?? 3 : 3
            perform(name, state)
            log("runner \(run) step \(name) screen=\(state.screen.rawValue) cancelled=\(Task.isCancelled)", directory)
            try? await Task.sleep(for: .seconds(seconds))
            log("runner \(run) capture \(name) screen=\(state.screen.rawValue)", directory)
            capture(to: URL(filePath: directory).appending(path: "\(name).png"))
        }
        NSApp.terminate(nil)
    }

    private static func log(_ message: String, _ directory: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        let url = URL(filePath: directory).appending(path: "log.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private static func perform(_ step: String, _ state: AppState) {
        let parts = step.split(separator: "-", maxSplits: 1).map(String.init)
        if let screen = Screen(rawValue: parts[0]) {
            state.screen = screen
        }
        guard parts.count > 1, let engine = state.engine else { return }
        switch step {
        case "junk-scan": state.junk.scan(with: engine)
        case "optimize-check": state.optimize.check(with: engine)
        case "developer-scan": state.developer.scan(with: engine)
        case "installers-scan": state.installers.scan()
        case "space-home": state.space.open(NSHomeDirectory(), named: "Home", with: engine)
        case "junk-expand": break
        default: break
        }
    }

    private static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif

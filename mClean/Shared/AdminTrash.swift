import Foundation

/// Moves items only an administrator can change (like system-wide audio
/// plug-ins) to the Trash, after macOS's own password prompt.
enum AdminTrash {
    struct Outcome {
        var moved: Set<String> = []
        var failed: Set<String> = []
        var cancelled = false
    }

    /// Runs mclean-admin-trash.sh as root. The script accepts only audio
    /// plug-in and preset folders and refuses everything else.
    static func move(_ paths: [String], reason: String) async -> Outcome {
        guard !paths.isEmpty else { return Outcome() }
        guard let script = Bundle.main.url(forResource: "mclean-admin-trash", withExtension: "sh") else {
            return Outcome(failed: Set(paths))
        }
        let arguments = ["/bin/bash", script.path, String(getuid()), String(getgid()), NSHomeDirectory()] + paths
        let command = arguments.map(shellQuoted).joined(separator: " ")
        let source = "do shell script \"\(appleScriptEscaped(command))\" with prompt \"\(appleScriptEscaped(reason))\" with administrator privileges"

        // NSAppleScript shows the prompt as mClean, so it runs on the main thread.
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) == -128 {
            return Outcome(cancelled: true)
        }

        var outcome = Outcome()
        let output = result?.stringValue ?? (error?[NSAppleScript.errorMessage] as? String) ?? ""
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { continue }
            if fields[0] == "moved" { outcome.moved.insert(fields[1]) } else { outcome.failed.insert(fields[1]) }
        }
        // Anything the script didn't report on wasn't moved.
        for path in paths where !outcome.moved.contains(path) && FileManager.default.fileExists(atPath: path) {
            outcome.failed.insert(path)
        }
        return outcome
    }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

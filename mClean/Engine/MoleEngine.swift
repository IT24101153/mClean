import Foundation

/// Runs the Mole command-line engine. The app ships its own copy of Mole in
/// `Contents/Resources/Mole`; an installed `mole` is used only as a fallback.
nonisolated struct MoleEngine: Sendable {
    /// What a command does, which decides how the app treats it while it runs.
    enum Purpose: Sendable {
        /// Live metrics. Never keeps the Mac awake.
        case monitor
        /// A read-only scan or preview the user is waiting for.
        case scan
        /// Removes or changes files. Quitting asks before stopping it.
        case change
    }

    let executableURL: URL
    let askpassURL: URL?
    let isBundled: Bool

    /// The folder that holds `mole`, `bin/` and `lib/`.
    var engineFolder: URL { executableURL.resolvingSymlinksInPath().deletingLastPathComponent() }

    static func locate() -> MoleEngine? {
        let fileManager = FileManager.default
        let askpass = Bundle.main.url(forResource: "askpass", withExtension: "sh")

        if let bundled = Bundle.main.resourceURL?.appending(path: "Mole/mole"),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return MoleEngine(executableURL: bundled, askpassURL: askpass, isBundled: true)
        }

        let home = NSHomeDirectory()
        for path in ["/opt/homebrew/bin/mole", "/usr/local/bin/mole", "\(home)/.local/bin/mole"]
        where fileManager.isExecutableFile(atPath: path) {
            return MoleEngine(executableURL: URL(filePath: path), askpassURL: askpass, isBundled: false)
        }
        return nil
    }

    /// Runs `mole <arguments>`, streaming each output line to `onLine`.
    /// - Parameters:
    ///   - input: Text written to the command's stdin, then stdin is closed.
    ///   - mergeErrors: Send stderr into the same stream as stdout.
    @discardableResult
    func run(
        _ arguments: [String],
        input: String? = nil,
        mergeErrors: Bool = true,
        purpose: Purpose = .scan,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> MoleRun {
        try await execute(executableURL, arguments, input: input, mergeErrors: mergeErrors,
                          purpose: purpose, onLine: onLine)
    }

    /// Runs one of mClean's helper scripts against this engine.
    func helper(_ name: String, _ arguments: [String], input: String? = nil,
                purpose: Purpose = .scan) async throws -> MoleRun {
        guard let script = Bundle.main.url(forResource: name, withExtension: "sh") else {
            throw MoleError.engineMissing
        }
        return try await execute(URL(filePath: "/bin/bash"), [script.path, engineFolder.path] + arguments,
                                 input: input, mergeErrors: false, purpose: purpose, onLine: { _ in })
    }

    private func execute(
        _ executable: URL,
        _ arguments: [String],
        input: String?,
        mergeErrors: Bool,
        purpose: Purpose,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> MoleRun {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = URL(filePath: NSHomeDirectory())
        process.environment = Self.environment(askpass: askpassURL)

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = mergeErrors ? output : errors

        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin

        let (exitCodes, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        let handle = ProcessHandle(process)
        return try await withTaskCancellationHandler {
            try process.run()
            let registration = RunningCommands.shared.add(handle, purpose: purpose)
            // Scans and cleanups shouldn't stall because the Mac idles or the
            // app is in the background.
            let activity = purpose == .monitor ? nil : ProcessInfo.processInfo.beginActivity(
                options: .userInitiated, reason: "Running a cleanup task")
            defer {
                RunningCommands.shared.remove(registration)
                if let activity { ProcessInfo.processInfo.endActivity(activity) }
            }

            if let input {
                try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                try? stdin.fileHandleForWriting.close()
            }

            let errorText: Task<String, Never>? = mergeErrors ? nil : Task.detached {
                let data = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
                return String(decoding: data, as: UTF8.self)
            }

            var collected = ""
            for try await line in output.fileHandleForReading.bytes.lines {
                collected += line + "\n"
                onLine(line)
            }

            var status: Int32 = -1
            for await code in exitCodes { status = code }
            let stderrText = await errorText?.value ?? ""

            if Task.isCancelled { throw CancellationError() }
            return MoleRun(exitCode: status, output: collected, errorOutput: stderrText)
        } onCancel: {
            handle.interrupt()
        }
    }

    /// Runs a command that prints JSON and decodes it.
    func json<T: Decodable & Sendable>(_ type: T.Type, _ arguments: [String], snakeCase: Bool = false,
                                       purpose: Purpose = .scan) async throws -> T {
        let result = try await run(arguments, mergeErrors: false, purpose: purpose)
        guard let start = result.output.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            throw MoleError.failed(result.failureMessage)
        }
        return try Self.decode(T.self, from: Data(result.output[start...].utf8), snakeCase: snakeCase)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, snakeCase: Bool) throws -> T {
        let decoder = JSONDecoder()
        if snakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MoleError.unreadableOutput(String(describing: error))
        }
    }

    /// First line of `mole --version`, e.g. "Mole version 1.59.1".
    func version() async -> String? {
        let result = try? await run(["--version"], purpose: .monitor)
        return result?.output.split(separator: "\n").first.map(String.init)
    }

    // MARK: Environment

    private static func environment(askpass: URL?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()

        // GUI apps start with a minimal PATH. Mole calls brew, npm, pip and
        // friends, so use the login shell's PATH plus the usual install spots.
        var paths = (ShellPath.login ?? env["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "\(home)/.local/bin",
                      "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !paths.contains(extra) {
            paths.append(extra)
        }
        env["PATH"] = paths.joined(separator: ":")
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["NO_COLOR"] = "1"
        env.removeValue(forKey: "MO_DEBUG")
        if let askpass {
            env["SUDO_ASKPASS"] = askpass.path
        }
        return env
    }
}

nonisolated struct MoleRun: Sendable {
    let exitCode: Int32
    let output: String
    let errorOutput: String

    var succeeded: Bool { exitCode == 0 }

    /// The most useful line to show when a command fails.
    var failureMessage: String {
        let lines = (errorOutput + "\n" + output)
            .split(separator: "\n")
            .map { MoleText.clean(String($0)) }
            .filter { !$0.isEmpty && !$0.hasPrefix("===") }
        return lines.last ?? "Mole exited with code \(exitCode)."
    }
}

nonisolated enum MoleError: LocalizedError {
    case engineMissing
    case failed(String)
    case unreadableOutput(String)

    var errorDescription: String? {
        switch self {
        case .engineMissing:
            "The cleaning engine is missing. Reinstall mClean."
        case .failed(let message):
            message
        case .unreadableOutput(let detail):
            "Couldn't read the engine's response. \(detail)"
        }
    }
}

/// Every engine command that is running, so quitting can stop them cleanly.
nonisolated final class RunningCommands: @unchecked Sendable {
    static let shared = RunningCommands()

    private let lock = NSLock()
    private var entries: [UUID: (handle: ProcessHandle, purpose: MoleEngine.Purpose)] = [:]

    fileprivate func add(_ handle: ProcessHandle, purpose: MoleEngine.Purpose) -> UUID {
        let id = UUID()
        lock.withLock { entries[id] = (handle, purpose) }
        return id
    }

    fileprivate func remove(_ id: UUID) {
        lock.withLock { _ = entries.removeValue(forKey: id) }
    }

    var isEmpty: Bool { lock.withLock { entries.isEmpty } }

    /// True while something is removing or changing files.
    var isChangingFiles: Bool { lock.withLock { entries.values.contains { $0.purpose == .change } } }

    /// Sends Ctrl-C to every command, the same as pressing Cancel.
    func interruptAll() {
        let handles = lock.withLock { entries.values.map(\.handle) }
        handles.forEach { $0.interrupt() }
    }
}

/// Lets the cancellation handler interrupt a running `Process`.
nonisolated final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func interrupt() {
        if process.isRunning {
            process.interrupt()
        }
    }
}

/// The user's login-shell PATH, read once.
nonisolated private enum ShellPath {
    static let login: String? = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-l", "-c", "/usr/bin/printenv PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.contains("/") ? path : nil
    }()
}

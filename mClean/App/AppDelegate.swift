import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quitting stops running engine commands the same way Cancel does, and
    /// asks first when one of them is removing files.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = RunningCommands.shared
        guard !running.isEmpty else { return .terminateNow }

        if running.isChangingFiles {
            let alert = NSAlert()
            alert.messageText = "A cleanup is still running"
            alert.informativeText = "Quitting stops it safely. Anything already cleaned stays cleaned, and nothing is left half-removed."
            alert.addButton(withTitle: "Keep Running")
            alert.addButton(withTitle: "Stop and Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                return .terminateCancel
            }
        }

        running.interruptAll()
        Task {
            // Give each command a moment to finish its current step and exit.
            for _ in 0..<50 where !running.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

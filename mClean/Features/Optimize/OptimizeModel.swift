import Foundation

/// Optimize drives `mole optimize`: refreshes caches, rebuilds indexes and
/// repairs preferences. It doesn't delete personal files.
@Observable
final class OptimizeModel {
    let job = MoleJob(preview: ["optimize", "--dry-run"], run: ["optimize"])

    func check(with engine: MoleEngine) {
        job.startPreview(with: engine)
    }

    func optimize(with engine: MoleEngine, onFinish: @escaping () -> Void) {
        Notifier.requestPermission()
        job.startRun(with: engine) {
            let detail = self.job.result?.summaryDetails.first ?? "Your Mac's caches and services are refreshed."
            Notifier.postIfInBackground("Optimization finished", MoleText.friendly(detail))
            onFinish()
        }
    }

    /// One row per maintenance task, in Mole's order.
    var tasks: [ReportSection] {
        (job.preview?.sections ?? []).filter { !$0.items.isEmpty }
    }

    /// "Likely bottleneck: WindowServer (~39% CPU sustained)" and similar.
    var diagnosis: [ReportItem] {
        job.preview?.preamble.filter { $0.state == .warning || $0.state == .review } ?? []
    }

    /// "Would apply 3 optimizations" -> 3
    var plannedCount: Int? {
        guard let line = job.preview?.summary.first(where: { $0.hasPrefix("Would apply") }) else { return nil }
        return line.split(separator: " ").compactMap { Int($0) }.first
    }

    /// "12 unchanged | 5 skipped | 2 unavailable" -> "12 already fine · 5 skipped · 2 unavailable"
    var outcomeSummary: String? {
        guard let line = job.preview?.summary.first(where: { $0.contains("unchanged") || $0.contains("skipped") })
        else { return nil }
        return line.components(separatedBy: " | ")
            .map { $0.replacingOccurrences(of: "unchanged", with: "already fine") }
            .joined(separator: " · ")
    }
}

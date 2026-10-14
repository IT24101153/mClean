import SwiftUI

struct OptimizeView: View {
    @Environment(AppState.self) private var state

    private var model: OptimizeModel { state.optimize }
    private let tint = Screen.optimize.tint

    var body: some View {
        Group {
            switch model.job.phase {
            case .idle:
                FeatureHero(symbol: Screen.optimize.symbol, tint: tint, title: "Optimize",
                            message: "Refresh caches, rebuild search indexes and repair broken preferences. Nothing personal is deleted.") {
                    Button("Check My Mac", action: check)
                        .primaryAction(tint: tint)
                }
            case .previewing:
                WorkingView(symbol: Screen.optimize.symbol, tint: tint, title: "Checking",
                            step: model.job.live.currentStep.map { "\($0)…" }, onCancel: model.job.cancel)
            case .ready:
                review
            case .running:
                WorkingView(symbol: Screen.optimize.symbol, tint: tint, title: "Optimizing",
                            step: model.job.live.currentStep.map { "\($0)…" }, onCancel: model.job.cancel)
            case .finished:
                DoneView(tint: tint, title: model.job.result?.summaryTitle?.capitalizedSentence ?? "Optimization complete",
                         details: model.job.result?.summaryDetails ?? []) {
                    model.job.dismissResult()
                }
            case .failed(let message):
                FailureView(message: message, tint: tint, retry: check)
            }
        }
        .animation(.smooth, value: model.job.phase)
    }

    private func check() {
        guard let engine = state.engine else { return }
        model.check(with: engine)
    }

    private var headline: String {
        model.plannedCount == 0 ? "Everything looks good" : "Ready to optimize"
    }

    private var review: some View {
        VStack(spacing: 0) {
            ResultHeader(bytes: nil, caption: headline, detail: model.outcomeSummary, tint: tint) {
                HStack(spacing: 10) {
                    Button("Recheck", action: check)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                    Button("Optimize") {
                        guard let engine = state.engine else { return }
                        model.optimize(with: engine) {
                            let detail = model.job.result?.summaryDetails.first.map(MoleText.friendly) ?? ""
                            state.activity.record(.optimized, "Mac optimized", detail)
                            state.didFreeSpace()
                        }
                    }
                    .primaryAction(tint: tint)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.diagnosis.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Performance", systemImage: "waveform.path.ecg")
                                .font(.headline)
                            ForEach(model.diagnosis) { item in
                                Text(item.title)
                                    .font(.callout)
                                    .foregroundStyle(item.state == .warning ? .primary : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 14)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 { Divider().padding(.leading, 58) }
                            TaskRow(task: task, tint: tint)
                        }
                    }
                    .card(padding: 6)

                    Text("Some tasks ask for your administrator password.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(24)
            }
        }
    }
}

private struct TaskRow: View {
    let task: ReportSection
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: SectionSymbols.symbol(for: task.title))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body.weight(.medium))
                Text(task.items.map(\.title).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            StatePill(status: TaskStatus(task), tint: tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct StatePill: View {
    let status: TaskStatus
    let tint: Color

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case .willRun: ("Will run", tint)
        case .healthy: ("Healthy", .green)
        case .skipped: ("Skipped", .secondary)
        case .unavailable: ("Unavailable", .secondary)
        case .attention: ("Needs attention", .yellow)
        }
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

extension String {
    /// "Dry Run Complete, No Changes Made" -> "Dry run complete, no changes made"
    var capitalizedSentence: String {
        let lower = lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

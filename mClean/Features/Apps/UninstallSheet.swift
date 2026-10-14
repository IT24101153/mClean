import SwiftUI

struct UninstallSheet: View {
    let flow: UninstallFlow

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var showKept = false

    private let tint = Screen.apps.tint

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
    }

    private var header: some View {
        HStack(spacing: 14) {
            FileIcon(path: flow.app.path, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(flow.app.name)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(22)
    }

    private var subtitle: String {
        if case .review(let plan) = flow.phase, let total = plan.totalSize.flatMap(ByteSize.parse) {
            return "\(ByteSize.format(total)) including related files"
        }
        return flow.app.displaySize
    }

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .preparing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Finding related files…")
                    .foregroundStyle(.secondary)
            }
        case .review(let plan):
            review(plan)
        case .removing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Moving \(flow.app.name) to the Trash…")
                    .foregroundStyle(.secondary)
            }
        case .finished(let report):
            finished(report)
        case .failed(let message):
            ContentUnavailableView("Couldn't uninstall", systemImage: "exclamationmark.triangle",
                                   description: Text(MoleText.friendly(message)))
        }
    }

    private func review(_ plan: UninstallPlan) -> some View {
        List {
            if plan.matchedApps > 1 {
                NoticeBanner(symbol: "exclamationmark.triangle",
                             text: "\(plan.matchedApps) apps share this name. All of them will be removed.")
                    .listRowSeparator(.hidden)
            }
            ForEach(plan.warnings, id: \.self) { warning in
                NoticeBanner(symbol: "info.circle", text: MoleText.friendly(warning), tint: .blue)
                    .listRowSeparator(.hidden)
            }
            Section("Moved to the Trash") {
                ForEach(plan.files) { PathRow(path: $0) }
            }
            if !plan.systemFiles.isEmpty {
                Section("System files · needs your password") {
                    ForEach(plan.systemFiles) { PathRow(path: $0) }
                }
            }
            if !plan.keptData.isEmpty {
                Section {
                    DisclosureGroup("Personal data kept (\(plan.keptData.count))", isExpanded: $showKept) {
                        ForEach(plan.keptData) { PathRow(path: $0) }
                    }
                } footer: {
                    Text("Settings and documents stay, in case you reinstall later.")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func finished(_ report: MoleReport) -> some View {
        let succeeded = report.summaryTitle == "Uninstall complete"
        return VStack(spacing: 14) {
            HeroBadge(symbol: succeeded ? "checkmark" : "exclamationmark", tint: succeeded ? .green : .orange, size: 84)
            Text(succeeded ? "\(flow.app.name) was removed" : "Uninstall incomplete")
                .font(.title2.weight(.semibold))
            ForEach(report.summaryDetails, id: \.self) { line in
                Text(MoleText.friendly(line))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 440)
            if succeeded {
                Text("You can still restore it from the Trash.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch flow.phase {
            case .review(let plan):
                Text("\(plan.files.count + plan.systemFiles.count) items")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) {
                    guard let engine = state.engine else { return }
                    let app = flow.app
                    flow.uninstall(with: engine) {
                        state.apps.forget(app)
                        state.didFreeSpace()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .tint(.red)
            case .removing:
                Spacer()
            case .finished, .failed:
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .preparing:
                Spacer()
                Button("Cancel") {
                    flow.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .controlSize(.large)
        .padding(16)
    }
}

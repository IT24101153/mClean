import SwiftUI

struct DeveloperView: View {
    @Environment(AppState.self) private var state
    @State private var confirming = false

    private var model: DeveloperModel { state.developer }
    private let tint = Screen.developer.tint

    var body: some View {
        Group {
            if let outcome = model.outcome {
                MovedToTrashView(tint: tint, outcome: outcome) { model.dismissOutcome() }
            } else if model.isTrashing {
                WorkingView(symbol: Screen.developer.symbol, tint: tint, title: "Moving to the Trash",
                            step: "Moving \(model.selection.count) folders…")
            } else {
                switch model.job.phase {
                case .idle, .running, .finished:
                    FeatureHero(symbol: Screen.developer.symbol, tint: tint, title: "Developer Junk",
                                message: "Find build folders and dependencies in your projects, like node_modules, build and .gradle.") {
                        Button("Scan Projects", action: scan)
                            .primaryAction(tint: tint)
                    }
                case .previewing:
                    WorkingView(symbol: Screen.developer.symbol, tint: tint, title: "Scanning projects",
                                step: "Looking for build folders…", bytes: model.liveBytes, onCancel: model.job.cancel)
                case .ready:
                    review
                case .failed(let message):
                    FailureView(message: message, tint: tint, retry: scan)
                }
            }
        }
        .animation(.smooth, value: model.job.phase)
        .alert("Move \(model.selection.count) folders (\(ByteSize.format(model.selectedBytes))) to the Trash?",
               isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    await model.moveSelectedToTrash(using: state.trash)
                    if let outcome = model.outcome { state.recordTrash(outcome, from: "Developer junk") }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.selectionHasDependencies
                 ? "Build output comes back when you build. Dependencies like node_modules come back when you install them, which needs an internet connection."
                 : "Build output comes back the next time you build.")
        }
    }

    private func scan() {
        guard let engine = state.engine else { return }
        model.scan(with: engine)
    }

    private var review: some View {
        VStack(spacing: 0) {
            ResultHeader(bytes: model.selectedBytes, caption: "selected in build folders and dependencies",
                         detail: "\(model.selection.count) of \(model.artifacts.count) folders · \(ByteSize.format(model.totalBytes)) found",
                         tint: tint) {
                HStack(spacing: 10) {
                    Button("Rescan", action: scan)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                    Button("Move to Trash") { confirming = true }
                        .primaryAction(tint: tint)
                        .disabled(model.selection.isEmpty)
                }
            }
            Divider()
            if model.artifacts.isEmpty {
                ContentUnavailableView("No build folders found", systemImage: "checkmark.seal",
                                       description: Text("Your projects are already lean."))
            } else {
                List {
                    Section {
                        ForEach(model.artifacts) { artifact in
                            ArtifactRow(artifact: artifact, isSelected: selectionBinding(for: artifact.path))
                        }
                    } header: {
                        HStack {
                            Text("\(model.artifacts.count) folders")
                            Spacer()
                            Button(model.allSelected ? "Deselect All" : "Select All") { model.toggleAll() }
                                .buttonStyle(.link)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func selectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { model.selection.contains(path) },
            set: { selected in
                if selected { model.selection.insert(path) } else { model.selection.remove(path) }
            }
        )
    }
}

private struct ArtifactRow: View {
    let artifact: ReportedPath
    @Binding var isSelected: Bool

    private var project: String {
        let parent = (artifact.expandedPath as NSString).deletingLastPathComponent
        return (parent as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        let kind = ArtifactKind(path: artifact)
        HStack(spacing: 12) {
            Toggle("Select \(artifact.name)", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            FileIcon(path: artifact.expandedPath, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(artifact.name)
                        .font(.body.weight(.medium))
                    Text(kind.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(kind == .dependencies ? .orange : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background((kind == .dependencies ? Color.orange : Color.secondary).opacity(0.12), in: Capsule())
                }
                Text(project)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 16)
            Text(artifact.displaySize ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
        .contextMenu {
            Button("Show in Finder") { Finder.reveal(artifact.expandedPath) }
        }
    }
}

import SwiftUI

struct InstallersView: View {
    @Environment(AppState.self) private var state
    @State private var confirming = false

    private var model: InstallersModel { state.installers }
    private let tint = Screen.installers.tint

    var body: some View {
        Group {
            if let outcome = model.outcome {
                MovedToTrashView(tint: tint, outcome: outcome) { model.dismissOutcome() }
            } else {
                switch model.phase {
                case .idle:
                    FeatureHero(symbol: Screen.installers.symbol, tint: tint, title: "Installers",
                                message: "Find disk images and installer packages you no longer need once the app is installed.") {
                        Button("Find Installers", action: model.scan)
                            .primaryAction(tint: tint)
                    }
                case .scanning:
                    WorkingView(symbol: Screen.installers.symbol, tint: tint, title: "Looking",
                                step: "Checking Downloads, Desktop and Documents…")
                case .trashing:
                    WorkingView(symbol: Screen.installers.symbol, tint: tint, title: "Moving to the Trash")
                case .ready:
                    review
                }
            }
        }
        .animation(.smooth, value: model.phase)
        .alert("Move \(model.selection.count) installers (\(ByteSize.format(model.selectedBytes))) to the Trash?",
               isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    await model.moveSelectedToTrash(using: state.trash)
                    if let outcome = model.outcome { state.recordTrash(outcome, from: "Installers") }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can put them back from the Trash until you empty it.")
        }
    }

    private var review: some View {
        VStack(spacing: 0) {
            ResultHeader(bytes: model.selectedBytes, caption: "selected in installers",
                         detail: "\(model.selection.count) of \(model.files.count) files · \(ByteSize.format(model.totalBytes)) found",
                         tint: tint) {
                HStack(spacing: 10) {
                    Button("Rescan", action: model.scan)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                    Button("Move to Trash") { confirming = true }
                        .primaryAction(tint: tint)
                        .disabled(model.selection.isEmpty)
                }
            }
            Divider()
            if model.files.isEmpty {
                ContentUnavailableView("No installers found", systemImage: "checkmark.seal",
                                       description: Text("Nothing left over in Downloads, Desktop or Documents."))
            } else {
                List {
                    Section {
                        ForEach(model.files) { file in
                            InstallerRow(file: file, isSelected: selectionBinding(for: file.path))
                        }
                    } header: {
                        HStack {
                            Text("\(model.files.count) files")
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

private struct InstallerRow: View {
    let file: InstallerFile
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Select \(file.name)", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            FileIcon(path: file.path, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(file.location)
                    if let modified = file.modified {
                        Text("·")
                        Text(modified, format: .dateTime.day().month().year())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Text(ByteSize.format(file.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
        .contextMenu {
            Button("Show in Finder") { Finder.reveal(file.path) }
        }
    }
}

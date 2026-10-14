import SwiftUI

struct SpaceView: View {
    @Environment(AppState.self) private var state
    @State private var deletion: DeletionStep?
    @State private var trashError: String?

    private var model: SpaceModel { state.space }
    private let tint = Screen.space.tint

    var body: some View {
        content
            .onAppear(perform: load)
            .alert(deletion?.title ?? "", isPresented: isDeleting, presenting: deletion) { step in
                switch step {
                case .confirm(let item):
                    Button("Delete", role: .destructive) { askAgain(item) }
                case .reconfirm(let item):
                    Button("Move to Trash", role: .destructive) { trash(item) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { step in
                Text(step.message)
            }
            .alert("Couldn't delete", isPresented: isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(trashError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.trail.isEmpty {
            if let error = model.error {
                FailureView(message: error, tint: tint, retry: load)
            } else {
                let cancel: (() -> Void)? = model.isLoading ? { model.cancel() } : nil
                WorkingView(symbol: Screen.space.symbol, tint: tint, title: "Disk Space",
                            step: "Measuring \(model.loadingName ?? "your disk")…", onCancel: cancel)
            }
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                listing
            }
        }
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { trashError != nil }, set: { if !$0 { trashError = nil } })
    }

    private var modeBinding: Binding<SpaceModel.Mode> {
        Binding(get: { model.mode }, set: { model.mode = $0 })
    }

    private func load() {
        guard let engine = state.engine else { return }
        model.loadIfNeeded(with: engine)
    }

    private func open(_ entry: DiskScan.Entry) {
        guard entry.isDirectory, let engine = state.engine else { return }
        model.open(entry.path, named: entry.name, with: engine)
    }

    // MARK: Deleting

    private func delete(path: String, name: String, size: Int64, isDirectory: Bool) {
        deletion = .confirm(DeletionItem(path: path, name: name, size: size, isDirectory: isDirectory))
    }

    /// The first alert has to finish closing before the second can appear.
    private func askAgain(_ item: DeletionItem) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            deletion = .reconfirm(item)
        }
    }

    private func trash(_ item: DeletionItem) {
        do {
            try model.moveToTrash(item.path, size: item.size)
            state.trash.didTrash(item.size)
            state.recordTrash(TrashBin.MoveOutcome(movedBytes: item.size, movedCount: 1), from: "“\(item.name)”")
            Task { await state.status.refresh() }
        } catch {
            trashError = error.localizedDescription
        }
    }

    private func deleteAction(path: String, name: String, size: Int64, isDirectory: Bool) -> (() -> Void)? {
        guard SpaceModel.canTrash(path) else { return nil }
        return { delete(path: path, name: name, size: size, isDirectory: isDirectory) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Breadcrumbs(trail: model.trail) { model.go(to: $0) }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    BigSize(bytes: model.currentTotal, tint: tint)
                    Text(model.current?.overview == true ? "measured in the folders below" : "in \(title(of: model.current))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let name = model.loadingName {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Measuring \(name)…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 8)
                }
                if state.trashBytes > 0 {
                    EmptyTrashButton(bytes: state.trashBytes, compact: true)
                }
                Button {
                    guard let engine = state.engine else { return }
                    model.rescan(with: engine)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Measure this folder again")
                .disabled(model.isLoading)
                Picker("View", selection: modeBinding) {
                    ForEach(SpaceModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func title(of scan: DiskScan?) -> String {
        guard let scan else { return "" }
        return (scan.path as NSString).lastPathComponent
    }

    // MARK: Listing

    @ViewBuilder
    private var listing: some View {
        switch model.mode {
        case .folders:
            let largest = max(model.entries.first?.size ?? 1, 1)
            List {
                if model.current?.scanStatus == "partial" && !state.permissions.hasFullDiskAccess {
                    FullDiskAccessNotice(reason: "Some folders need Full Disk Access to be measured.")
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(model.entries) { entry in
                        entryRow(entry, largest: largest)
                    }
                }
                if !model.insights.isEmpty {
                    Section("Worth a look") {
                        ForEach(model.insights) { entry in
                            entryRow(entry, largest: largest)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.entries.isEmpty && model.insights.isEmpty {
                    ContentUnavailableView("Empty folder", systemImage: "folder")
                }
            }
        case .largeFiles:
            let largest = max(model.largeFiles.first?.size ?? 1, 1)
            List(model.largeFiles) { file in
                SizeRow(path: file.path, name: file.name, size: file.size, fraction: Double(file.size) / Double(largest),
                        tint: tint, isDirectory: false,
                        onDelete: deleteAction(path: file.path, name: file.name, size: file.size, isDirectory: false))
                    .contextMenu { menu(path: file.path, name: file.name, size: file.size, isDirectory: false) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.largeFiles.isEmpty {
                    ContentUnavailableView("No large files here", systemImage: "doc")
                }
            }
        }
    }

    private func entryRow(_ entry: DiskScan.Entry, largest: Int64) -> some View {
        SizeRow(path: entry.path, name: entry.name, size: entry.size, fraction: Double(entry.size) / Double(largest),
                tint: tint, isDirectory: entry.isDirectory, highlighted: entry.insight == true,
                onDelete: deleteAction(path: entry.path, name: entry.name, size: entry.size, isDirectory: entry.isDirectory))
            .onTapGesture { open(entry) }
            .contextMenu {
                if entry.isDirectory {
                    Button("Open") { open(entry) }
                }
                menu(path: entry.path, name: entry.name, size: entry.size, isDirectory: entry.isDirectory)
            }
    }

    @ViewBuilder
    private func menu(path: String, name: String, size: Int64, isDirectory: Bool) -> some View {
        Button("Show in Finder") { Finder.reveal(path) }
        if let action = deleteAction(path: path, name: name, size: size, isDirectory: isDirectory) {
            Divider()
            Button("Delete…", role: .destructive, action: action)
        }
    }
}

// MARK: - Deletion

private struct DeletionItem {
    let path: String
    let name: String
    let size: Int64
    let isDirectory: Bool
}

/// Deleting asks twice: once to choose, once to be sure.
private enum DeletionStep {
    case confirm(DeletionItem)
    case reconfirm(DeletionItem)

    var title: String {
        switch self {
        case .confirm(let item): "Delete “\(item.name)”?"
        case .reconfirm: "Are you sure?"
        }
    }

    var message: String {
        switch self {
        case .confirm(let item):
            let what = item.isDirectory ? "This folder and everything in it" : "This file"
            return "\(what) (\(ByteSize.format(item.size))) will be moved to the Trash."
        case .reconfirm(let item):
            return "“\(item.name)” will be moved to the Trash. Empty the Trash to free \(ByteSize.format(item.size))."
        }
    }
}

// MARK: - Rows

private struct SizeRow: View {
    let path: String
    let name: String
    let size: Int64
    let fraction: Double
    let tint: Color
    let isDirectory: Bool
    var highlighted = false
    var onDelete: (() -> Void)?

    @State private var hovering = false
    @State private var hoveringDelete = false

    var body: some View {
        HStack(spacing: 12) {
            FileIcon(path: path, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .lineLimit(1)
                    if highlighted {
                        Image(systemName: "sparkle")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                CapacityBar(fraction: fraction, tint: tint.opacity(0.85), height: 4)
                    .frame(maxWidth: 320)
            }
            Spacer(minLength: 16)
            Text(ByteSize.format(size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Group {
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(hoveringDelete ? Color.red : Color.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                    .onHover { hoveringDelete = $0 }
                } else {
                    Color.clear
                }
            }
            .frame(width: 24)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(isDirectory ? 1 : 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(hovering && isDirectory ? Color.primary.opacity(0.04) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .help(path)
    }
}

private struct Breadcrumbs: View {
    let trail: [DiskScan]
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(trail.enumerated()), id: \.offset) { index, scan in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Button(label(for: scan, index: index)) { onSelect(index) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == trail.count - 1 ? .primary : .secondary)
                    .font(index == trail.count - 1 ? .headline : .body)
            }
            Spacer()
        }
        .lineLimit(1)
    }

    private func label(for scan: DiskScan, index: Int) -> String {
        if scan.overview == true { return "Macintosh HD" }
        if scan.path == NSHomeDirectory() { return "Home" }
        return (scan.path as NSString).lastPathComponent
    }
}

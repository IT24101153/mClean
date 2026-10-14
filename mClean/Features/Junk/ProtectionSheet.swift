import SwiftUI

/// Lets people choose what System Junk must never clean.
struct ProtectionSheet: View {
    var onSaved: () -> Void = {}

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ProtectionModel.Item] = []
    @State private var customPatterns: [String] = []
    @State private var query = ""
    @State private var saving = false
    @State private var problem: String?

    private var model: ProtectionModel { state.protection }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Never Clean")
                    .font(.title2.weight(.semibold))
                Text("Protected items are skipped every time System Junk cleans.")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
            }
            .padding(20)
            Divider()

            Group {
                if model.isLoading && items.isEmpty {
                    ProgressView()
                } else if let error = model.error, items.isEmpty {
                    ContentUnavailableView("Couldn't read the protection list", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Text("\(items.filter(\.isProtected).count + customPatterns.count) protected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || items.isEmpty)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 560, height: 600)
        .task {
            guard let engine = state.engine else { return }
            await model.load(with: engine)
            items = model.items
            customPatterns = model.customPatterns
        }
        .alert("Couldn't save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private var list: some View {
        List {
            let visible = items.indices.filter { matches(items[$0].name) || matches(items[$0].pattern) }
            let categories = Array(Set(visible.map { items[$0].category })).sorted {
                ProtectionModel.categoryTitle($0) < ProtectionModel.categoryTitle($1)
            }
            ForEach(categories, id: \.self) { category in
                Section(ProtectionModel.categoryTitle(category)) {
                    ForEach(visible.filter { items[$0].category == category }, id: \.self) { index in
                        Toggle(isOn: $items[index].isProtected) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(items[index].name)
                                Text(display(items[index].pattern))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
            }

            let custom = customPatterns.filter(matches)
            if !custom.isEmpty {
                Section {
                    ForEach(custom, id: \.self) { pattern in
                        HStack {
                            Text(display(pattern))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                customPatterns.removeAll { $0 == pattern }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Stop protecting this")
                        }
                    }
                } header: {
                    Text("Other protected paths")
                } footer: {
                    Text("Includes the engine's own defaults, such as downloaded AI models.")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }

    private func display(_ pattern: String) -> String {
        if pattern == "FINDER_METADATA" { return ".DS_Store files" }
        let home = NSHomeDirectory()
        return pattern.hasPrefix(home) ? "~" + pattern.dropFirst(home.count) : pattern
    }

    private func save() {
        guard let engine = state.engine else { return }
        saving = true
        Task {
            do {
                try await model.save(items: items, customPatterns: customPatterns, with: engine)
                dismiss()
                onSaved()
            } catch {
                problem = error.localizedDescription
            }
            saving = false
        }
    }
}

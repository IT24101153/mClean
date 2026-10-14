import SwiftUI

struct AppsView: View {
    @Environment(AppState.self) private var state
    @State private var flow: UninstallFlow?

    private var model: AppsModel { state.apps }
    private let tint = Screen.apps.tint

    var body: some View {
        @Bindable var model = model

        Group {
            if model.apps.isEmpty && model.isLoading {
                WorkingView(symbol: Screen.apps.symbol, tint: tint, title: "Applications",
                            step: "Reading your applications…")
            } else if model.apps.isEmpty, let error = model.error {
                FailureView(message: error, tint: tint, retry: reload)
            } else {
                VStack(spacing: 0) {
                    header(query: $model.query, sort: $model.sort)
                    Divider()
                    list
                }
            }
        }
        .task {
            guard let engine = state.engine else { return }
            await model.loadIfNeeded(with: engine)
        }
        .sheet(item: $flow) { flow in
            UninstallSheet(flow: flow)
        }
    }

    private func header(query: Binding<String>, sort: Binding<AppsModel.Sort>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Applications")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Text("\(model.apps.count) apps · \(ByteSize.format(model.totalBytes))")
                        .monospacedDigit()
                    if model.isLoading {
                        ProgressView().controlSize(.mini)
                        Text("Updating…")
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            SearchField(text: query)
                .frame(width: 220)
            Picker("Sort", selection: sort) {
                ForEach(AppsModel.Sort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            Button(action: reload) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(model.isLoading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var list: some View {
        List {
            ForEach(model.visibleApps) { app in
                AppRow(app: app, tint: tint) { flow = makeFlow(for: app) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.visibleApps.isEmpty && !model.query.isEmpty {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }

    private func makeFlow(for app: InstalledApp) -> UninstallFlow? {
        guard let engine = state.engine else { return nil }
        let flow = UninstallFlow(app: app)
        flow.prepare(with: engine)
        return flow
    }

    private func reload() {
        guard let engine = state.engine else { return }
        Task { await model.load(with: engine) }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let tint: Color
    let onUninstall: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            FileIcon(path: app.path, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if app.isHomebrew {
                        Text("Homebrew")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text((app.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 16)
            Text(app.displaySize)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Uninstall", action: onUninstall)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onUninstall)
        .contextMenu {
            Button("Uninstall…", action: onUninstall)
            Button("Show in Finder") { Finder.reveal(app.path) }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

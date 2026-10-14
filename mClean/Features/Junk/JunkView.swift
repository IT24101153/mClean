import SwiftUI

struct JunkView: View {
    @Environment(AppState.self) private var state
    @State private var confirmingClean = false
    @State private var choosingProtection = false

    private var model: JunkModel { state.junk }
    private let tint = Screen.junk.tint

    var body: some View {
        Group {
            switch model.job.phase {
            case .idle:
                FeatureHero(symbol: "sparkles", tint: tint, title: "System Junk",
                            message: "Find caches, logs and leftovers from deleted apps that are safe to remove.") {
                    VStack(spacing: 14) {
                        Button("Scan", action: scan)
                            .primaryAction(tint: tint)
                        Button("Choose what never gets cleaned") { choosingProtection = true }
                            .buttonStyle(.link)
                    }
                }
            case .previewing:
                WorkingView(symbol: "sparkles", tint: tint, title: "Scanning",
                            step: model.job.live.currentStep.map { "Looking at \($0.lowercased())…" },
                            bytes: model.liveBytes, onCancel: model.job.cancel)
            case .ready:
                results
            case .running:
                WorkingView(symbol: "sparkles", tint: tint, title: "Cleaning",
                            step: model.job.live.currentStep.map { "Cleaning \($0.lowercased())…" },
                            bytes: model.liveBytes, bytesLabel: "cleaned", onCancel: model.job.cancel)
            case .finished:
                DoneView(tint: tint, title: finishedTitle, details: model.job.result?.summaryDetails ?? []) {
                    model.job.dismissResult()
                }
            case .failed(let message):
                FailureView(message: message, tint: tint, retry: scan)
            }
        }
        .animation(.smooth, value: model.job.phase)
        .alert("Clean \(ByteSize.format(model.cleanableBytes ?? 0)) of junk?", isPresented: $confirmingClean) {
            Button("Clean", role: .destructive) {
                guard let engine = state.engine else { return }
                model.clean(with: engine) { state.didFreeSpace() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Caches and logs are deleted permanently. Apps recreate what they need.")
        }
        .sheet(isPresented: $choosingProtection) {
            ProtectionSheet {
                // A preview made before the change would show protected items.
                if model.job.phase == .ready { scan() }
            }
        }
    }

    private var finishedTitle: String {
        if let freed = model.freedBytes { return "Freed \(ByteSize.format(freed))" }
        return "Your Mac is clean"
    }

    private func scan() {
        guard let engine = state.engine else { return }
        model.scan(with: engine) { state.protection.scanned() }
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            ResultHeader(bytes: model.cleanableBytes, caption: "ready to clean",
                         detail: model.previewDetail, tint: tint) {
                HStack(spacing: 10) {
                    Button {
                        choosingProtection = true
                    } label: {
                        Image(systemName: "lock.shield")
                    }
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .help("Choose what never gets cleaned")
                    Button("Rescan", action: scan)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                    Button("Clean") { confirmingClean = true }
                        .primaryAction(tint: tint)
                        .disabled((model.cleanableBytes ?? 0) == 0 && model.cleanableSections.isEmpty)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.needsFullDiskAccess && !state.permissions.hasFullDiskAccess {
                        FullDiskAccessNotice(reason: "The Trash and some caches need Full Disk Access.")
                    }

                    if !state.protection.recentlyProtected.isEmpty {
                        NoticeBanner(symbol: "lock.shield",
                                     text: "Protected items are skipped from now on. Rescan to update the total.",
                                     tint: tint) {
                            Button("Rescan", action: scan)
                                .controlSize(.small)
                        }
                    }

                    if model.cleanableSections.isEmpty {
                        ContentUnavailableView("Nothing to clean", systemImage: "checkmark.seal",
                                               description: Text("Your caches and logs are already tidy."))
                            .padding(.vertical, 30)
                    }

                    ForEach(model.cleanableSections) { section in
                        JunkSectionCard(section: section, paths: model.paths[section.title] ?? [], tint: tint)
                    }

                    if !model.reviewItems.isEmpty {
                        ReviewCard(items: model.reviewItems)
                            .padding(.top, 8)
                    }

                    Text("Protected files and anything in use are skipped automatically.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(24)
            }
        }
    }
}

// MARK: - Section card

private struct JunkSectionCard: View {
    let section: ReportSection
    let paths: [ReportedPath]
    let tint: Color

    @Environment(AppState.self) private var state
    @State private var expanded = false
    @State private var showAllPaths = false
    @State private var problem: String?

    private func protect(_ path: ReportedPath) {
        guard let engine = state.engine else { return }
        Task {
            do {
                try await state.protection.protect(path.expandedPath, with: engine)
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: SectionSymbols.symbol(for: section.title))
                        .font(.title3)
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.items.map(\.title).joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Text(ByteSize.format(section.totalBytes))
                        .font(.headline)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.items) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text(item.detail ?? "")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                    if !paths.isEmpty {
                        Divider().padding(.vertical, 4)
                        let visible = showAllPaths ? paths : Array(paths.prefix(8))
                        ForEach(visible) { path in
                            PathRow(path: path,
                                    isProtected: state.protection.recentlyProtected.contains(path.expandedPath),
                                    onProtect: { protect(path) })
                        }
                        if paths.count > 8 {
                            Button(showAllPaths ? "Show less" : "Show all \(paths.count) files") {
                                withAnimation(.snappy) { showAllPaths.toggle() }
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                        }
                    }
                }
                .padding(.leading, 46)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(padding: 14)
        .alert("Couldn't protect that item", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }
}

/// Large items Mole only points out, like simulators or emulator images.
private struct ReviewCard: View {
    let items: [ReportItem]
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Worth a look", systemImage: "eye")
                .font(.headline)
            Text("These aren't removed automatically. Review them yourself if you need more space.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                        if let path = item.mentionedPath {
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if let bytes = item.bytes {
                        Text(ByteSize.format(bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if let path = item.mentionedPath {
                        Button("Show") { Finder.reveal(path) }
                            .controlSize(.small)
                    } else if (item.detail ?? "").contains("mo purge") {
                        Button("Review") { state.screen = .developer }
                            .controlSize(.small)
                    }
                }
                .font(.callout)
            }
        }
        .card(padding: 14)
    }
}

enum SectionSymbols {
    static func symbol(for title: String) -> String {
        let key = title.lowercased()
        let table: [(String, String)] = [
            ("user", "person.crop.circle"),
            ("browser", "globe"),
            ("cloud", "icloud"),
            ("developer", "chevron.left.forwardslash.chevron.right"),
            ("virtual", "server.rack"),
            ("leftover", "shippingbox"),
            ("support", "folder"),
            ("update", "arrow.down.circle"),
            ("backup", "iphone"),
            ("time machine", "clock.arrow.circlepath"),
            ("large", "doc.zipper"),
            ("project", "hammer"),
            ("system", "gearshape"),
            ("app", "app.badge"),
            ("dns", "network"),
            ("network", "network"),
            ("spotlight", "magnifyingglass"),
            ("finder", "folder"),
            ("database", "cylinder"),
            ("permission", "lock"),
            ("login", "person.badge.key"),
            ("disk", "internaldrive"),
            ("notification", "bell"),
            ("launch", "power"),
            ("quarantine", "checkmark.shield"),
            ("config", "wrench.adjustable"),
            ("usage", "chart.bar"),
            ("maintenance", "calendar"),
            ("state", "rectangle.stack"),
            (".ds_store", "eye.slash"),
            ("override", "slider.horizontal.3"),
            ("shared file", "list.bullet"),
        ]
        return table.first { key.contains($0.0) }?.1 ?? "folder"
    }
}

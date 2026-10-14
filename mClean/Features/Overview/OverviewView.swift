import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state

    private var snapshot: StatusSnapshot? { state.status.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                HStack(alignment: .top, spacing: 16) {
                    HealthCard(score: snapshot?.healthScore, message: snapshot?.healthScoreMsg)
                        .frame(width: 220)
                    VStack(spacing: 16) {
                        StorageCard(disk: snapshot?.startupDisk, trashBytes: state.trashBytes)
                        HStack(spacing: 16) {
                            MetricCard(title: "Memory", symbol: "memorychip",
                                       percent: snapshot?.memory?.usedPercent,
                                       caption: memoryCaption)
                            MetricCard(title: "CPU", symbol: "cpu",
                                       percent: snapshot?.cpu?.usage,
                                       caption: snapshot?.hardware?.cpuModel.flatMap { $0.isEmpty ? nil : $0 } ?? " ")
                            if let battery = snapshot?.batteries?.first {
                                MetricCard(title: "Battery", symbol: "battery.75percent",
                                           percent: battery.percent, caption: battery.health.map { "Health: \($0)" } ?? " ",
                                           tint: .green)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick actions")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ActionTile(screen: .junk, subtitle: junkSubtitle)
                        ActionTile(screen: .apps, subtitle: appsSubtitle)
                        ActionTile(screen: .space, subtitle: "See what's taking up space")
                        ActionTile(screen: .optimize, subtitle: "Refresh caches and system services")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .task { await state.status.watch() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(machineLine)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var machineLine: String {
        let hardware = snapshot?.hardware
        let parts = [hardware?.model, hardware?.osVersion, snapshot?.uptime.map { "up \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Reading your Mac…" : parts.joined(separator: "  ·  ")
    }

    private var memoryCaption: String {
        guard let used = snapshot?.memory?.used, let total = snapshot?.memory?.total else { return " " }
        return "\(ByteSize.format(used)) of \(ByteSize.format(total))"
    }

    private var junkSubtitle: String {
        if let bytes = state.junk.cleanableBytes, bytes > 0 {
            return "\(ByteSize.format(bytes)) ready to clean"
        }
        return "Caches, logs and leftovers"
    }

    private var appsSubtitle: String {
        state.apps.apps.isEmpty ? "Remove apps and their leftovers" : "\(state.apps.apps.count) apps installed"
    }
}

// MARK: - Cards

private struct HealthCard: View {
    let score: Int?
    let message: String?

    private var tint: Color {
        guard let score else { return .secondary }
        return score >= 80 ? .green : score >= 60 ? .yellow : .red
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.8), value: score)
                VStack(spacing: 0) {
                    Text(score.map(String.init) ?? "–")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Health")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, height: 130)
            Text(message ?? "Checking…")
                .font(.headline)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .card()
    }
}

private struct StorageCard: View {
    let disk: StatusSnapshot.Disk?
    let trashBytes: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                if let disk, let used = disk.used, let total = disk.total {
                    Text("\(ByteSize.format(used)) of \(ByteSize.format(total)) used")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let disk, let used = disk.used, let total = disk.total, total > 0 {
                let fraction = Double(used) / Double(total)
                CapacityBar(fraction: fraction, tint: fraction > 0.9 ? .red : .accentColor, height: 12)
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteSize.format(total - used))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text("available")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let trashBytes, trashBytes > 0 {
                        Label("\(ByteSize.format(trashBytes)) in Trash", systemImage: "trash")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        EmptyTrashButton(bytes: trashBytes)
                            .controlSize(.small)
                    }
                }
            } else {
                CapacityBar(fraction: 0, height: 12)
                Text("Measuring…")
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

private struct MetricCard: View {
    let title: String
    let symbol: String
    let percent: Double?
    let caption: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "–")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: percent)
            CapacityBar(fraction: (percent ?? 0) / 100, tint: tint, height: 5)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

private struct ActionTile: View {
    let screen: Screen
    let subtitle: String

    @Environment(AppState.self) private var state
    @State private var hovering = false

    var body: some View {
        Button {
            state.screen = screen
        } label: {
            HStack(spacing: 14) {
                Image(systemName: screen.symbol)
                    .font(.title2)
                    .foregroundStyle(screen.tint.gradient)
                    .frame(width: 46, height: 46)
                    .background(screen.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(screen.title)
                        .font(.headline)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .offset(x: hovering ? 2 : 0)
            }
            .contentShape(Rectangle())
            .card(padding: 14)
            .scaleEffect(hovering ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
    }
}

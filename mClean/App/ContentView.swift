import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @AppStorage("didShowWelcome") private var didShowWelcome = false

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            Sidebar(selection: $state.screen)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                if state.engine == nil {
                    EngineMissingView()
                } else {
                    detail(for: state.screen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
        .task { await state.status.refresh() }
        .sheet(isPresented: Binding(get: { !didShowWelcome }, set: { if !$0 { didShowWelcome = true } })) {
            WelcomeView()
        }
        #if DEBUG
        .task { await DebugSnapshots.runIfRequested(state) }
        #endif
    }

    @ViewBuilder
    private func detail(for screen: Screen) -> some View {
        switch screen {
        case .overview: OverviewView()
        case .junk: JunkView()
        case .apps: AppsView()
        case .space: SpaceView()
        case .installers: InstallersView()
        case .audio: AudioView()
        case .optimize: OptimizeView()
        case .developer: DeveloperView()
        case .history: HistoryView()
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: Screen
    @Environment(AppState.self) private var state

    var body: some View {
        List(selection: $selection) {
            BrandMark()
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .padding(.bottom, 6)
            row(.overview)
            Section("Clean") {
                row(.junk)
                row(.apps)
                row(.space)
                row(.installers)
            }
            Section("Audio") {
                row(.audio)
            }
            Section("Maintain") {
                row(.optimize)
                row(.developer)
                row(.history)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            DiskFooter(snapshot: state.status.snapshot)
                .padding(14)
        }
    }

    private func row(_ screen: Screen) -> some View {
        Label {
            Text(screen.title)
        } icon: {
            Image(systemName: screen.symbol)
                .foregroundStyle(screen.tint == .accentColor ? Color.accentColor : screen.tint)
        }
        .tag(screen)
    }
}

/// Free space on the startup disk, always visible at the bottom of the sidebar.
private struct DiskFooter: View {
    let snapshot: StatusSnapshot?

    var body: some View {
        if let disk = snapshot?.startupDisk, let total = disk.total, let used = disk.used, total > 0 {
            let fraction = Double(used) / Double(total)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text("Macintosh HD")
                        .font(.callout.weight(.medium))
                    Spacer()
                }
                CapacityBar(fraction: fraction, tint: fraction > 0.9 ? .red : .accentColor, height: 6)
                Text("\(ByteSize.format(total - used)) free of \(ByteSize.format(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct EngineMissingView: View {
    var body: some View {
        FeatureHero(symbol: "shippingbox", tint: .orange, title: "Engine not found",
                    message: "mClean couldn't find its cleaning engine. Reinstall the app, or install Mole with Homebrew: brew install mole")
    }
}

/// The app's logo and name at the top of the sidebar.
struct BrandMark: View {
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
            Text("mClean")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("mClean")
    }
}

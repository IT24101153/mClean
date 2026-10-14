import SwiftUI

// MARK: - Hero

/// The centered "one thing to do" layout every screen starts from.
struct FeatureHero<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var busy = false
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 18) {
            HeroBadge(symbol: symbol, tint: tint, busy: busy)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .contentTransition(.opacity)
            }
            actions
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension FeatureHero where Actions == EmptyView {
    init(symbol: String, tint: Color, title: String, message: String, busy: Bool = false) {
        self.init(symbol: symbol, tint: tint, title: title, message: message, busy: busy) { EmptyView() }
    }
}

struct HeroBadge: View {
    let symbol: String
    let tint: Color
    var busy = false
    var size: CGFloat = 112

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.gradient.opacity(0.14))
            Circle()
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            if busy {
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .padding(1.5)
                    .onAppear {
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
                    }
                    .onDisappear { spin = false }
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(tint.gradient)
                .symbolEffect(.pulse, isActive: busy)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Buttons

struct PrimaryActionStyle: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .tint(tint)
    }
}

extension View {
    func primaryAction(tint: Color) -> some View {
        modifier(PrimaryActionStyle(tint: tint))
    }

    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            )
    }
}

// MARK: - Results header

/// "1.6 GB ready to clean" with the screen's main action on the right.
struct ResultHeader<Actions: View>: View {
    let bytes: Int64?
    let caption: String
    var detail: String?
    let tint: Color
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                if let bytes {
                    BigSize(bytes: bytes, tint: tint)
                }
                Text(caption)
                    .font(.title3.weight(.medium))
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            actions
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }
}

struct BigSize: View {
    let bytes: Int64
    var tint: Color = .primary

    var body: some View {
        let parts = ByteSize.parts(bytes)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.value)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(parts.unit)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint.gradient)
        .monospacedDigit()
    }
}

// MARK: - Bars

struct CapacityBar: View {
    var fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.smooth, value: fraction)
    }
}

// MARK: - Files

struct FileIcon: View {
    let path: String
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// A file or folder row: icon, name, location and size.
struct PathRow: View {
    let path: ReportedPath
    var tint: Color = .secondary
    var isProtected = false
    /// Offers "Never Clean This" when set.
    var onProtect: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(path: path.expandedPath, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(path.name)
                    .lineLimit(1)
                Text(path.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if isProtected {
                Label("Protected", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let size = path.displaySize {
                Text(size)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .opacity(isProtected ? 0.6 : 1)
        .contextMenu {
            Button("Show in Finder") { Finder.reveal(path.expandedPath) }
            if let onProtect, !isProtected {
                Divider()
                Button("Never Clean This", action: onProtect)
            }
        }
    }
}

enum Finder {
    static func reveal(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: expanded)])
        } else {
            NSWorkspace.shared.open(URL(filePath: (expanded as NSString).deletingLastPathComponent))
        }
    }
}

// MARK: - Notices

struct NoticeBanner<Action: View>: View {
    let symbol: String
    let text: String
    var tint: Color = .orange
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension NoticeBanner where Action == EmptyView {
    init(symbol: String, text: String, tint: Color = .orange) {
        self.init(symbol: symbol, text: text, tint: tint) { EmptyView() }
    }
}

/// Shown when a feature fails. Keeps the engine's own words.
struct FailureView: View {
    let message: String
    let tint: Color
    let retry: () -> Void

    var body: some View {
        FeatureHero(symbol: "exclamationmark.triangle", tint: .orange,
                    title: "Something went wrong", message: MoleText.friendly(message)) {
            Button("Try Again", action: retry)
                .primaryAction(tint: tint)
        }
    }
}

// MARK: - Progress and completion

/// Shown while Mole works: the current step and a running total.
struct WorkingView: View {
    let symbol: String
    let tint: Color
    let title: String
    var step: String?
    var bytes: Int64?
    var bytesLabel = "found so far"
    var onCancel: (() -> Void)?

    var body: some View {
        FeatureHero(symbol: symbol, tint: tint, title: title, message: step ?? "Getting ready…", busy: true) {
            VStack(spacing: 16) {
                if let bytes, bytes > 0 {
                    Text("\(ByteSize.format(bytes)) \(bytesLabel)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: bytes)
                }
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                }
            }
        }
    }
}

/// The finish line: what happened, in one sentence, and a way back.
struct DoneView: View {
    let tint: Color
    let title: String
    let details: [String]
    var buttonTitle = "Done"
    let onDone: () -> Void

    var body: some View {
        FeatureHero(symbol: "checkmark", tint: tint, title: title,
                    message: details.isEmpty ? "All done." : details.map(MoleText.friendly).joined(separator: "\n")) {
            Button(buttonTitle, action: onDone)
                .primaryAction(tint: tint)
        }
    }
}

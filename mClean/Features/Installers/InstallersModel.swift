import Foundation

/// Installers finds disk images and packages left over in Downloads and
/// similar folders, then moves the ones you pick to the Trash.
@Observable
final class InstallersModel {
    enum Phase: Equatable {
        case idle, scanning, ready, trashing
    }

    private(set) var phase: Phase = .idle
    private(set) var files: [InstallerFile] = []
    private(set) var outcome: TrashBin.MoveOutcome?
    var selection: Set<String> = []

    var totalBytes: Int64 { files.map(\.size).reduce(0, +) }
    var selectedFiles: [InstallerFile] { files.filter { selection.contains($0.path) } }
    var selectedBytes: Int64 { selectedFiles.map(\.size).reduce(0, +) }
    var allSelected: Bool { !files.isEmpty && selection.count == files.count }

    func scan() {
        outcome = nil
        phase = .scanning
        Task {
            files = await Task.detached { InstallerScanner.scan() }.value
            selection = Set(files.map(\.path))
            phase = .ready
        }
    }

    func toggleAll() {
        selection = allSelected ? [] : Set(files.map(\.path))
    }

    func moveSelectedToTrash(using trash: TrashModel) async {
        Notifier.requestPermission()
        phase = .trashing
        let result = await trash.move(selectedFiles.map { (path: $0.path, size: $0.size) })
        outcome = result
        files = []
        selection = []
        phase = .idle
    }

    func dismissOutcome() {
        outcome = nil
    }
}

import Foundation

@Observable
final class StatusModel {
    private(set) var snapshot: StatusSnapshot?
    private let engine: MoleEngine?

    init(engine: MoleEngine?) {
        self.engine = engine
    }

    /// Takes one snapshot.
    func refresh() async {
        guard let engine,
              var next = try? await engine.json(StatusSnapshot.self, ["status", "--json"], snakeCase: true,
                                                purpose: .monitor)
        else { return }
        next.keepHardware(from: snapshot)
        snapshot = next
    }

    /// Streams live metrics until the calling task is cancelled.
    func watch() async {
        guard let engine else { return }
        _ = try? await engine.stream(["status", "--watch", "--interval", "2s"], purpose: .monitor) { line in
            guard line.hasPrefix("{"),
                  var next = try? MoleEngine.decode(StatusSnapshot.self, from: Data(line.utf8), snakeCase: true)
            else { return }
            next.keepHardware(from: snapshot)
            snapshot = next
        }
    }
}

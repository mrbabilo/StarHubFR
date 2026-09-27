import Foundation

/// Les cas réels du parc et un manifeste Nexus réel, extraits par
/// `make_triage_fixtures.py`, lus à côté de ce fichier (patron `#filePath`).
enum Fixture {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

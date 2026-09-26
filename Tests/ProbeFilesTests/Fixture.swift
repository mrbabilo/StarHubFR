import Foundation

/// Les fichiers réels de la sonde, extraits par `make_fixtures.py`, lus à côté
/// de ce fichier (le patron `#filePath` de `SmapiInstallerInvocationTests`).
enum Fixture {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

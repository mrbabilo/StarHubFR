import Foundation
import Testing
@testable import StarHubTHCore

/// L'analyse d'une archive ne doit jamais se figer.
///
/// Constaté le 2026-08-27 en installant un mod Nexus : l'app restait sur
/// « Analyse de l'archive… », avec deux `/usr/bin/unzip -Z1` vivants et
/// immobiles à 0 % de processeur. `hasTraversalEntry` appelait
/// `waitUntilExit()` **avant** de vider le tube ; passé la capacité de
/// celui-ci — 64 Ko sur macOS —, l'enfant bloque sur son écriture et le
/// parent sur son attente.
///
/// Le test fabrique une archive dont le seul listing dépasse cette capacité.
/// Sans le correctif il ne se termine pas : d'où la limite de temps explicite,
/// qui transforme un blocage en échec lisible plutôt qu'en suite de tests
/// suspendue.
@Suite struct ArchiveListingTests {

    /// Une archive dont le listing pèse plus que la capacité d'un tube.
    private func makeWideArchive(entries: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wide-\(UUID().uuidString)", isDirectory: true)
        let content = root.appendingPathComponent("MonMod", isDirectory: true)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        for index in 0..<entries {
            // Des noms longs : c'est le volume du **listing** qui compte, pas
            // celui des fichiers.
            let name = String(format: "UnDossierAuNomAssezLongPourRemplirLeTampon_%05d", index)
            let directory = content.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: directory.appendingPathComponent("fichier_\(index).json"))
        }

        let archive = root.appendingPathComponent("mod.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qr", archive.path, "MonMod"]
        zip.currentDirectoryURL = root
        try zip.run()
        zip.waitUntilExit()
        return archive
    }

    /// Exécute `body` en fond et échoue si elle n'a pas rendu la main à temps.
    /// Un blocage laisse le fil de fond suspendu — sans conséquence : le
    /// processus de test se termine, et c'est le verdict qui compte.
    private func withDeadline<T: Sendable>(_ seconds: Double,
                                           _ body: @escaping @Sendable () -> T) -> T? {
        let box = Mutex<T?>(nil)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let value = body()
            box.set(value)
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds) == .success else { return nil }
        return box.get()
    }

    @Test func listingAWideArchiveDoesNotDeadlock() throws {
        let archive = try makeWideArchive(entries: 900)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

        // Le listing de cette archive dépasse 64 Ko : c'est précisément ce qui
        // faisait tenir l'enfant et le parent chacun de son côté.
        let outcome: Bool? = withDeadline(30) {
            ModZipInstaller.hasTraversalEntry(zipUrl: archive, ext: "zip")
        }
        let listing = try #require(outcome,
                                   "l'analyse s'est figée — le tube est lu après l'attente")
        // Aucune entrée en `../` : l'archive est saine.
        #expect(listing == false)
    }
}

/// Un porteur de valeur protégé, le temps du test.
private final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func set(_ newValue: Value) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
}

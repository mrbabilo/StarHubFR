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

/// Un zip dont les noms d'entrées ne sont pas de l'UTF-8 valide.
///
/// Les vieux zips encodent leurs noms à la mode DOS. `/usr/bin/unzip` refuse
/// alors de les créer sur APFS — « Illegal byte sequence », statut 2 — **après
/// avoir extrait le reste** : le dossier restait à moitié rempli et
/// l'installation échouait sans rien dire.
///
/// Mesuré sur « Kalash's More Fruit Trees » (Nexus 41318), dont un dossier
/// s'appelle `X ↓Unnecessary` : `unzip` rend 315 fichiers sur 320, `7zz` et
/// `unar` les 320 en transcodant le nom.
@Suite struct NonUTF8ArchiveTests {

    /// Construit un zip dont une entrée porte trois octets illégaux en UTF-8.
    ///
    /// On ne peut pas créer un tel nom sur APFS — le système le refuse aussi.
    /// L'archive est donc forgée : `zip` l'écrit avec un nom ASCII de même
    /// longueur, puis les octets sont remplacés sur place. La longueur étant
    /// identique, tous les décalages internes du zip restent valides.
    private func makeArchiveWithNonUTF8Name() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonutf8-\(UUID().uuidString)", isDirectory: true)
        let odd = root.appendingPathComponent("MonMod/assets/X ABCUnnecessary", isDirectory: true)
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: odd.appendingPathComponent("extra.png"))
        try Data(#"{"Name":"Mon Mod","UniqueID":"kalash.test","Version":"1.0.0"}"#.utf8)
            .write(to: root.appendingPathComponent("MonMod/manifest.json"))

        let archive = root.appendingPathComponent("mod.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qr", archive.path, "MonMod"]
        zip.currentDirectoryURL = root
        try zip.run()
        zip.waitUntilExit()

        // `ABC` → `D4 E5 F4`, la séquence même qui fait trébucher `unzip`.
        var bytes = try Data(contentsOf: archive)
        let needle = Data("X ABCUnnecessary".utf8)
        let replacement = Data([0x58, 0x20, 0xD4, 0xE5, 0xF4]) + Data("Unnecessary".utf8)
        #expect(replacement.count == needle.count)
        var searchFrom = bytes.startIndex
        var patched = 0
        while let found = bytes[searchFrom...].range(of: needle) {
            bytes.replaceSubrange(found, with: replacement)
            searchFrom = found.upperBound
            patched += 1
        }
        // En-tête local **et** répertoire central portent le nom : les deux
        // doivent être corrigés, sinon `unzip` signale une archive incohérente
        // et le test mesurerait la mauvaise panne.
        #expect(patched >= 2)
        try bytes.write(to: archive)
        return archive
    }

    @Test func anArchiveWithNonUTF8NamesStillExtractsWhole() throws {
        let archive = try makeArchiveWithNonUTF8Name()
        let root = archive.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        // Sans le repli, `unzip` rend 2 et l'extraction lève : le manifeste
        // manquerait, et l'installation refuserait une archive pourtant saine.
        let notes = try ModZipInstaller.extractArchive(zipUrl: archive, to: destination)

        let manifest = destination.appendingPathComponent("MonMod/manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifest.path))

        let files = FileManager.default.enumerator(at: destination,
                                                   includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        // Le fichier au nom illisible pour `unzip` fait partie du lot.
        #expect(files?.count == 2)

        // Et le journal en garde la trace : une extraction qui s'y reprend à
        // deux fois ne doit pas être silencieuse.
        #expect(notes.contains { $0.contains("unzip a rendu le statut") })
        #expect(notes.contains { $0.contains("extraction reprise") })
    }
}

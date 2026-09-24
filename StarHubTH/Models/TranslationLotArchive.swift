import Foundation

/// Le conteneur du lot multi-mods : un ZIP **plat**, un JSON de lot par mod.
///
/// Fabriqué et relu par les outils du système — `/usr/bin/zip` et
/// `/usr/bin/unzip`, les mêmes binaires que `ModZipInstaller` fait parler
/// dans l'autre sens. Rien n'est compressé par nos soins : un lot est du
/// JSON, déjà petit, et le format ZIP géré par Info-ZIP est le seul que le
/// traducteur extérieur ouvre sans nous.
///
/// Les pièges de `Process` y sont traités au niveau du type : locale
/// verrouillée en C (les tailles d'`unzip -l` ne se parsent pas en français),
/// tube lu **avant** `waitUntilExit` (au-delà de 64 Ko, l'enfant bloque
/// sinon), `-o` sur toute extraction (une archive à chemins dupliqués pose
/// sinon une question sur un stdin qui n'existe pas dans une app GUI).
public enum TranslationLotArchive {

    public enum Failure: Error, Equatable, Sendable {
        /// `zip` n'a pas produit d'archive — entrée vide, disque.
        case cannotCreateArchive
        /// Les octets ne portent pas la signature ZIP : refusés avant tout
        /// `unzip` — la signature, pas le nom, fait foi.
        case notAZip
        /// `unzip` a échoué.
        case extractionFailed
    }

    /// Fabrique l'archive. `files` porte des noms **plats** : un `/` ou un
    /// `..` dans un nom est une erreur d'appelant, pas un chemin.
    public static func make(files: [String: Data]) throws -> Data {
        guard !files.isEmpty else { throw Failure.cannotCreateArchive }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("lot-\(UUID().uuidString)", isDirectory: true)
        let staging = work.appendingPathComponent("in", isDirectory: true)
        let archive = work.appendingPathComponent("lot.zip")
        defer { discard(work) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var names: [String] = []
        for (name, data) in files.sorted(by: { $0.key < $1.key }) {
            guard !name.contains("/"), name != "..", name != "." else {
                throw Failure.cannotCreateArchive
            }
            try data.write(to: staging.appendingPathComponent(name))
            names.append(name)
        }
        try run("/usr/bin/zip", arguments: ["-q", "-X", "-j", archive.path]
            + names.map { staging.appendingPathComponent($0).path })
        guard FileManager.default.fileExists(atPath: archive.path) else {
            throw Failure.cannotCreateArchive
        }
        do {
            return try Data(contentsOf: archive)
        } catch {
            throw Failure.cannotCreateArchive
        }
    }

    /// Relit une archive : ses entrées JSON, à plat, par nom. Le reste
    /// (README, dossiers) est ignoré — un traducteur range ses notes à côté,
    /// ce n'est pas une erreur.
    public static func extract(_ data: Data) throws -> [String: Data] {
        guard data.starts(with: [0x50, 0x4B]) else { throw Failure.notAZip }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("lot-\(UUID().uuidString)", isDirectory: true)
        let out = work.appendingPathComponent("out", isDirectory: true)
        defer { discard(work) }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let payload = work.appendingPathComponent("lot.zip")
        try data.write(to: payload)
        try run("/usr/bin/unzip", arguments: ["-o", "-q", "-j", payload.path, "-d", out.path])
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: out, includingPropertiesForKeys: nil)
        } catch {
            throw Failure.extractionFailed
        }
        var files: [String: Data] = [:]
        for url in urls where url.pathExtension.lowercased() == "json" {
            // Une entrée illisible après extraction (droits) : ignorée, la
            // fusion nommera le mod manquant plutôt que d'avaler des octets
            // douteux.
            do {
                files[url.lastPathComponent] = try Data(contentsOf: url)
            } catch {
                continue
            }
        }
        return files
    }

    /// Le nettoyage d'un dossier temporaire n'a pas de suite utile quand il
    /// échoue — mais l'échec se dit, il ne se tait pas derrière un `try?`.
    private static func discard(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // Dossier déjà parti : le seul échec attendu.
        }
    }

    /// Lance l'outil, lève en cas d'échec. Le tube se lit **avant**
    /// `waitUntilExit` — un tube est borné, au-delà de 64 Ko l'enfant bloquerait
    /// sur son écriture et le parent sur son attente.
    private static func run(_ path: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ChildProcessEnvironment.localeLocked(to: "C")
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw Failure.extractionFailed
        }
        let _ = output.fileHandleForReading.readDataToEndOfFile()
        let _ = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.extractionFailed }
    }
}

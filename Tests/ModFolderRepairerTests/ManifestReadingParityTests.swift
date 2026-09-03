import Foundation
import Testing
@testable import StarHubTHCore

/// **Le réparateur lit-il un manifeste comme tout le reste du dépôt ?**
///
/// La détection de doublons relit chaque `manifest.json` du disque. Le scan,
/// l'installation et la sauvegarde passent tous par `ManifestJSON.decode` —
/// qui retire la marque d'ordre des octets, les commentaires et les virgules
/// traînantes. Mesuré sur le parc le 2026-09-04 : **142 des 1 095 manifestes
/// portent une marque d'octets**.
@Suite struct ManifestReadingParityTests {

    private func writeRawManifest(in dir: URL, bytes: Data) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appendingPathComponent("manifest.json"))
    }

    private func manifest(uniqueId: String, withBOM: Bool) -> Data {
        var data = withBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
        data.append(#"{"Name":"T","UniqueID":"\#(uniqueId)","Version":"1.0.0","Author":"T"}"#
            .data(using: .utf8)!)
        return data
    }

    @Test func aManifestWithAByteOrderMarkIsStillRead() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        try writeRawManifest(in: env.modsDir.appendingPathComponent("Mod"),
                             bytes: manifest(uniqueId: "dup.mod", withBOM: true))
        try writeRawManifest(in: env.modsDir.appendingPathComponent(".Mod"),
                             bytes: manifest(uniqueId: "dup.mod", withBOM: true))

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.duplicates.map(\.uniqueId) == ["dup.mod"])
    }

    @Test func aManifestWithoutAMarkIsReadTheSameWay() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        try writeRawManifest(in: env.modsDir.appendingPathComponent("Mod"),
                             bytes: manifest(uniqueId: "dup.mod", withBOM: false))
        try writeRawManifest(in: env.modsDir.appendingPathComponent(".Mod"),
                             bytes: manifest(uniqueId: "dup.mod", withBOM: false))

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.duplicates.map(\.uniqueId) == ["dup.mod"])
    }
}

/// **Le balayage profond teste le nom avant de toucher au disque.**
///
/// Il parcourt tout l'arbre de `Mods/` à chaque scan de lancement (le scan
/// passe `includeRepair: true` par défaut). Sur le parc de référence, cet
/// arbre compte **93 784 entrées** et **aucune** ne porte un nom de résidu
/// système : tout ce qui suit le test de nom ne sert donc jamais. Ces tests
/// fixent le comportement que l'ordre des gardes ne doit pas changer.
@Suite struct DeepJunkSweepTests {

    @Test func aCarriageReturnIconFileIsStillMatched() throws {
        // `Icon\r` porte réellement un retour chariot — c'est l'icône
        // personnalisée d'un dossier. Le test de nom porte désormais sur
        // `lastPathComponent` : si l'URL mangeait ce caractère, ce fichier
        // cesserait d'être reconnu.
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        let mod = env.modsDir.appendingPathComponent("IconMod")
        try writeManifest(in: mod, uniqueId: "icon.mod")
        try writeFile(in: mod, filename: "Icon\r", content: "")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.map(\.relativePath) == ["IconMod/Icon\r"])
        #expect(!FileManager.default.fileExists(atPath: mod.appendingPathComponent("Icon\r").path))
        // Le mod lui-même n'a pas bougé.
        #expect(FileManager.default.fileExists(atPath: mod.appendingPathComponent("manifest.json").path))
    }

    @Test func aFolderNamedLikeAJunkFileIsLeftAlone() throws {
        // Le test de nom passant en premier, la vérification « ce n'est pas un
        // dossier » reste indispensable : un dossier nommé `.DS_Store` ne se
        // met pas en quarantaine par ce chemin.
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        let mod = env.modsDir.appendingPathComponent("Mod")
        try writeManifest(in: mod, uniqueId: "some.mod")
        let trap = mod.appendingPathComponent(".DS_Store", isDirectory: true)
        try FileManager.default.createDirectory(at: trap, withIntermediateDirectories: true)
        try writeFile(in: trap, filename: "inside.txt")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.isEmpty)
        #expect(FileManager.default.fileExists(atPath: trap.appendingPathComponent("inside.txt").path))
    }
}

/// Les dossiers de métadonnées **pointés** (`.Spotlight-V100`, `.Trashes`)
/// sont dans `OSJunk.folders` ; la garde du premier niveau ne testait que les
/// *fichiers*, si bien qu'ils étaient écartés comme des mods en pause au lieu
/// d'être mis en quarantaine. Aucun n'est présent sur le parc de référence :
/// défaut latent, corrigé par cohérence — c'est exactement l'amputation qui a
/// fait naître `OSJunk`.
@Suite struct DottedJunkFolderTests {

    @Test func aDottedJunkFolderIsQuarantined() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        try writeManifest(in: env.modsDir.appendingPathComponent("RealMod"), uniqueId: "real.mod")
        let spotlight = env.modsDir.appendingPathComponent(".Spotlight-V100", isDirectory: true)
        try writeFile(in: spotlight, filename: "index.db")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.map(\.kind) == [.osJunkFolder])
        #expect(!FileManager.default.fileExists(atPath: spotlight.path))
    }

    @Test func aPausedModIsStillLeftAlone() throws {
        // La garde reste une garde : un vrai mod en pause ne doit rien subir.
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        let paused = env.modsDir.appendingPathComponent(".PausedMod")
        try writeManifest(in: paused, uniqueId: "paused.mod")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.isEmpty)
        #expect(FileManager.default.fileExists(atPath: paused.appendingPathComponent("manifest.json").path))
    }
}

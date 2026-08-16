import Testing
import Foundation
@testable import StarHubTHCore

/// Ce fichier est le travail du traducteur. Une écriture qui échoue à mi-chemin,
/// ou qui écrase sans filet, lui coûte des heures.
struct TranslationFileStoreTests {

    private func makeDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("i18n-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writingCreatesTheFile() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("fr.json")
        try TranslationFileStore.write("{\"a\":\"A\"}\n", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"a\":\"A\"}\n")
    }

    @Test func theFormerContentIsKeptAsBackup() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("fr.json")
        try TranslationFileStore.write("ancien\n", to: url)
        try TranslationFileStore.write("nouveau\n", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "nouveau\n")
        #expect(try String(contentsOf: TranslationFileStore.backupURL(for: url),
                           encoding: .utf8) == "ancien\n")
    }

    @Test func aFirstWriteLeavesNoBackup() throws {
        // Un `.bak` vide ferait croire à une version antérieure qui n'a jamais
        // existé — et inviterait à « restaurer » vers rien.
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("fr.json")
        try TranslationFileStore.write("premier\n", to: url)
        #expect(FileManager.default.fileExists(
            atPath: TranslationFileStore.backupURL(for: url).path) == false)
    }

    @Test func theBackupAlwaysHoldsTheImmediatelyPreviousVersion() throws {
        // Trois écritures : le `.bak` suit, il ne fige pas la première.
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("fr.json")
        try TranslationFileStore.write("un\n", to: url)
        try TranslationFileStore.write("deux\n", to: url)
        try TranslationFileStore.write("trois\n", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "trois\n")
        #expect(try String(contentsOf: TranslationFileStore.backupURL(for: url),
                           encoding: .utf8) == "deux\n")
    }

    @Test func noTemporaryFileSurvivesASuccessfulWrite() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("fr.json")
        try TranslationFileStore.write("ok\n", to: url)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(left.contains { $0.hasSuffix(".tmp") } == false)
    }

    @Test func writingIntoAMissingDirectoryFailsWithoutCrashing() {
        let url = URL(fileURLWithPath: "/nexistepas-\(UUID().uuidString)/fr.json")
        #expect(throws: (any Error).self) {
            try TranslationFileStore.write("x\n", to: url)
        }
    }

    @Test func aFailedWriteLeavesTheExistingFileIntact() throws {
        // Le dossier disparaît entre deux écritures : la seconde doit échouer
        // sans rien détruire de récupérable.
        let dir = makeDir()
        let url = dir.appendingPathComponent("fr.json")
        try TranslationFileStore.write("intact\n", to: url)
        let backup = TranslationFileStore.backupURL(for: url)
        #expect(FileManager.default.fileExists(atPath: backup.path) == false)
        #expect(try String(contentsOf: url, encoding: .utf8) == "intact\n")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func unicodeSurvivesTheRoundTrip() throws {
        // Accents, emoji et CJK traversent l'écriture sans se déformer : le
        // fichier est écrit en UTF-8, pas dans l'encodage du système.
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("fr.json")
        let content = "{\"a\":\"Été 🌾 日本語\"}\n"
        try TranslationFileStore.write(content, to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == content)
    }
}

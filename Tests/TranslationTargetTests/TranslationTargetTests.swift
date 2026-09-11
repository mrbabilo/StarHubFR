import Foundation
import Testing
@testable import StarHubTHCore

/// Un dossier `i18n` jetable, peuplé de fichiers réels.
///
/// Les contenus sont donnés en octets quand l'encodage fait partie du cas
/// éprouvé (UTF-16, CRLF) — le parc en porte, et un décodage naïf y perdrait
/// des fichiers entiers.
private struct I18nFixture {
    let root: URL
    var directory: URL { root.appendingPathComponent("i18n", isDirectory: true) }

    init(_ files: [String: Data]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("translation-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (relative, data) in files {
            let url = directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    init(text files: [String: String]) throws {
        try self.init(files.mapValues { Data($0.utf8) })
    }

    func cleanup() {
        // Un test rend un fichier illisible : le rouvrir, sinon la suppression
        // échoue et le dossier temporaire survit à la suite.
        if let entries = FileManager.default.enumerator(atPath: root.path) {
            for case let path as String in entries {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                       ofItemAtPath: root.appendingPathComponent(path).path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }
}

/// Où une traduction s'écrit — la décision que `saveTranslation` prenait au
/// milieu de 240 lignes de ViewModel, et que rien ne vérifiait.
///
/// Ce qui se joue ici n'est pas cosmétique : écrire `fr.json` à la racine d'un
/// dossier rangé en layout B fait **cesser** la lecture de tous ses
/// sous-dossiers par SMAPI, pour toutes les locales. 5 mods du parc de
/// référence sont en layout B avec du français (mesuré le 2026-09-11).
struct TranslationTargetTests {

    // MARK: - La locale existe déjà

    @Test func layoutAWritesIntoTheExistingLocaleFile() throws {
        let fixture = try I18nFixture(text: ["default.json": #"{"greet": "Hello"}"#,
                                             "fr.json": #"{"greet": "Bonjour"}"#])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "greet").success)
        #expect(resolved.file.lastPathComponent == "fr.json")
        #expect(resolved.key == "greet")
        #expect(resolved.sourceFile.lastPathComponent == "default.json")
        #expect(resolved.sourceText.contains("Hello"))
    }

    @Test func anExistingKeyKeepsItsOwnCase() throws {
        // SMAPI compare ses clés en `OrdinalIgnoreCase` : écrire `Greet` à côté
        // de `greet` créerait un doublon que le jeu tranche sans nous.
        let fixture = try I18nFixture(text: ["default.json": #"{"Greet": "Hello"}"#,
                                             "fr.json": #"{"GREET": "Bonjour"}"#])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "Greet").success)
        #expect(resolved.key == "GREET")
    }

    @Test func aNewKeyTakesTheCaseItWasAskedWith() throws {
        let fixture = try I18nFixture(text: ["default.json": #"{"Greet": "Hello"}"#,
                                             "fr.json": "{}"])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "Greet").success)
        #expect(resolved.key == "Greet")
        #expect(resolved.file.lastPathComponent == "fr.json")
    }

    @Test func layoutBWritesIntoTheFileThatCarriesTheKey() throws {
        // Forme réelle (`.Merchant`) : plusieurs sections par locale. Le fichier
        // qui porte déjà la clé gagne — y compris quand ce n'est pas le premier
        // dans l'ordre alphabétique.
        let fixture = try I18nFixture(text: [
            "default/dialogue.json": #"{"hi": "Hi"}"#,
            "default/items.json": #"{"sword": "Sword"}"#,
            "fr/dialogue.json": #"{"hi": "Salut"}"#,
            "fr/items.json": #"{"sword": "Épée"}"#,
        ])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "sword").success)
        #expect(resolved.file.lastPathComponent == "items.json")
    }

    @Test func theSourceFollowsTheChosenTargetFile() throws {
        // La source ne sert qu'au rang des clés neuves : prendre `dialogue.json`
        // pour une clé rangée dans `items.json` donnerait un rang qui n'existe
        // pas dans la cible.
        let fixture = try I18nFixture(text: [
            "default/dialogue.json": #"{"hi": "Hi"}"#,
            "default/items.json": #"{"sword": "Sword"}"#,
            "fr/dialogue.json": #"{"hi": "Salut"}"#,
            "fr/items.json": #"{"sword": "Épée"}"#,
        ])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "sword").success)
        #expect(resolved.sourceFile.lastPathComponent == "items.json")
    }

    @Test func aSingleLocaleFileAcceptsAKeyItDoesNotCarryYet() throws {
        // Le cas central de l'écran : une ligne « À traduire ». Aucun choix à
        // faire, donc aucune raison de refuser.
        let fixture = try I18nFixture(text: [
            "default/dialogue.json": #"{"hi": "Hi", "bye": "Bye"}"#,
            "fr/dialogue.json": #"{"hi": "Salut"}"#,
        ])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "bye").success)
        #expect(resolved.file.lastPathComponent == "dialogue.json")
        #expect(resolved.key == "bye")
    }

    @Test func severalLocaleFilesWithoutTheKeyAreRefusedRatherThanGuessed() throws {
        let fixture = try I18nFixture(text: [
            "default/dialogue.json": #"{"hi": "Hi"}"#,
            "default/items.json": #"{"sword": "Sword", "shield": "Shield"}"#,
            "fr/dialogue.json": #"{"hi": "Salut"}"#,
            "fr/items.json": #"{"sword": "Épée"}"#,
        ])
        defer { fixture.cleanup() }

        let refusal = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                             locale: "fr", key: "shield").failure)
        #expect(refusal == .keyAbsentFromEveryLocaleFile(key: "shield", locale: "fr",
                                                         fileCount: 2,
                                                         i18nPath: fixture.directory.path))
        #expect(refusal.reason.contains("shield"))
        #expect(refusal.reason.contains("2 fichiers"))
    }

    // MARK: - La locale n'existe pas encore

    @Test func aMissingLocaleIsCreatedAtTheRootOfALayoutADirectory() throws {
        let fixture = try I18nFixture(text: ["default.json": #"{"greet": "Hello"}"#,
                                             "en.json": #"{"greet": "Hello"}"#])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "greet").success)
        #expect(resolved.file.lastPathComponent == "fr.json")
        #expect(!FileManager.default.fileExists(atPath: resolved.file.path))
    }

    @Test func aMissingLocaleIsRefusedRatherThanShadowALayoutBDirectory() throws {
        // Le défaut que ce refus ferme : un seul `.json` à la racine suffit à
        // faire ignorer TOUS les sous-dossiers, pour toutes les locales. Créer
        // `fr.json` ici casserait les traductions déjà installées.
        let fixture = try I18nFixture(text: [
            "default/dialogue.json": #"{"hi": "Hi"}"#,
            "de/dialogue.json": #"{"hi": "Hallo"}"#,
        ])
        defer { fixture.cleanup() }

        let refusal = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                             locale: "fr", key: "hi").failure)
        #expect(refusal == .localeWouldShadowLayoutB(locale: "fr", i18nPath: fixture.directory.path))
    }

    @Test func aDirectoryWithoutASourceIsRefused() throws {
        let fixture = try I18nFixture(text: ["fr.json": #"{"greet": "Bonjour"}"#])
        defer { fixture.cleanup() }

        let refusal = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                             locale: "fr", key: "greet").failure)
        #expect(refusal == .noSource(i18nPath: fixture.directory.path))
    }

    @Test func anUnreadableSourceIsRefusedRatherThanWrittenBlind() throws {
        let fixture = try I18nFixture(text: ["default.json": #"{"greet": "Hello"}"#,
                                             "fr.json": #"{"greet": "Bonjour"}"#])
        defer { fixture.cleanup() }
        let source = fixture.directory.appendingPathComponent("default.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: source.path)

        let refusal = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                             locale: "fr", key: "greet").failure)
        // Le chemin rendu est celui que l'énumération du dossier a produit —
        // liens symboliques suivis (`/var/…` → `/private/var/…`), ce que
        // `resolvingSymlinksInPath()` ne défait pas. C'est donc le suffixe qui
        // s'éprouve, pas l'égalité de chaînes.
        guard case .unreadableSource(let path) = refusal else {
            Issue.record("refus attendu : source illisible, reçu \(refusal)")
            return
        }
        #expect(path.hasSuffix("i18n/default.json"))
        #expect(refusal.reason.hasSuffix("default.json illisible"))
    }

    // MARK: - Ce que le parc porte réellement

    @Test func aUTF16LocaleFileIsStillSearchedForItsKeys() throws {
        // Le parc porte des i18n en UTF-16, LE et BE : `String(data:encoding:.utf8)`
        // y rend `nil` et la clé passerait pour absente — donc, en layout B à
        // plusieurs fichiers, un refus au lieu d'un enregistrement.
        var utf16 = Data([0xFF, 0xFE])
        utf16.append(contentsOf: Array(#"{"sword": "Épée"}"#.utf16).flatMap {
            [UInt8($0 & 0xFF), UInt8($0 >> 8)]
        })
        let fixture = try I18nFixture([
            "default/dialogue.json": Data(#"{"hi": "Hi"}"#.utf8),
            "default/items.json": Data(#"{"sword": "Sword"}"#.utf8),
            "fr/dialogue.json": Data(#"{"hi": "Salut"}"#.utf8),
            "fr/items.json": utf16,
        ])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "sword").success)
        #expect(resolved.file.lastPathComponent == "items.json")
    }

    @Test func aCRLFLocaleFileIsStillSearchedForItsKeys() throws {
        let fixture = try I18nFixture(text: [
            "default/dialogue.json": "{\r\n  \"hi\": \"Hi\"\r\n}",
            "default/items.json": "{\r\n  \"sword\": \"Sword\"\r\n}",
            "fr/dialogue.json": "{\r\n  \"hi\": \"Salut\"\r\n}",
            "fr/items.json": "{\r\n  \"sword\": \"Épée\"\r\n}",
        ])
        defer { fixture.cleanup() }

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "sword").success)
        #expect(resolved.file.lastPathComponent == "items.json")
    }

    @Test func aFileWrittenByTheRealWriterIsFoundAgain() throws {
        // La fixture est produite par le chemin d'écriture réel
        // (`TranslationDocument` + `TranslationFileStore`), pas tapée à la
        // main : une fixture écrite à la main décrit un état que le vrai
        // producteur ne génère jamais.
        let fixture = try I18nFixture(text: ["default.json": #"{"a": "A", "b": "B"}"#])
        defer { fixture.cleanup() }
        let source = try #require(FileManager.default.contents(
            atPath: fixture.directory.appendingPathComponent("default.json").path))
        let text = try TranslationDocument.create(fromSource: String(decoding: source, as: UTF8.self),
                                                 translations: ["b": "Bé"])
        try TranslationFileStore.write(text, to: fixture.directory.appendingPathComponent("fr.json"))

        let resolved = try #require(TranslationTarget.resolve(inI18nDirectory: fixture.directory,
                                                              locale: "fr", key: "b").success)
        #expect(resolved.file.lastPathComponent == "fr.json")
        #expect(resolved.key == "b")
    }
}

private extension Result where Success == TranslationTarget.Destination,
                               Failure == TranslationTarget.Refusal {
    var success: TranslationTarget.Destination? { try? get() }
    var failure: TranslationTarget.Refusal? {
        if case .failure(let refusal) = self { return refusal }
        return nil
    }
}

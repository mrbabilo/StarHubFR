import Foundation
import Testing
@testable import StarHubTHCore

/// Une mise à jour apporte le `fr.json` de l'auteur alors qu'une traduction
/// locale existe (2026-10-03) : comparer, puis garder, prendre ou fusionner.
@Suite struct TranslationUpdateTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    private let local = """
    // Traduction locale (StarHubFR)
    {
      "greeting": "Bonjour",
      "farewell": "Au revoir local"
    }
    """
    private let author = #"{ "greeting": "Bonjour", "farewell": "Adieu", "thanks": "Merci \"beaucoup\"" }"#

    @Test func comparisonCountsBothSides() {
        let c = TranslationUpdate.Comparison.compare(
            local: ["a": "1", "b": "2", "c": "3"], author: ["a": "1", "b": "X", "d": "4"])
        #expect(c == .init(localKeys: 3, authorKeys: 3, differing: 1, authorOnly: 1, localOnly: 1))
        #expect(TranslationUpdate.Comparison.compare(local: ["a": "1"], author: ["a": "1"]).isIdentical)
    }

    /// Fusion : la locale intacte (commentaire, ordre, ses valeurs), la clé
    /// manquante de l'auteur ajoutée, échappée, et le tout relisible.
    @Test func mergeKeepsLocalLinesAndAddsMissingKeys() throws {
        let merged = try #require(TranslationUpdate.merged(
            localText: local, local: ["greeting": "Bonjour", "farewell": "Au revoir local"],
            author: ["greeting": "Bonjour", "farewell": "Adieu", "thanks": #"Merci "beaucoup""#]))
        #expect(merged.hasPrefix("// Traduction locale (StarHubFR)\n{"))
        let entries = try I18nLenientParser.parse(merged)
        #expect(entries["farewell"] == "Au revoir local")
        #expect(entries["thanks"] == #"Merci "beaucoup""#)
        #expect(entries.count == 3)
        // Une `{` dans un commentaire de tête n'est pas l'accolade ouvrante.
        #expect(TranslationUpdate.openingBrace(in: "/* { */ {}").map { "/* { */ {}".distance(from: "/* { */ {}".startIndex, to: $0) } == 8)
    }

    @Test func applyHonoursEachChoiceAndShelvesTheDiscardedFile() throws {
        for choice in [TranslationUpdate.Choice.keepLocal, .takeAuthor, .merge] {
            let root = try tempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("archive"), destination = root.appendingPathComponent("Mods/X")
            let shelf = root.appendingPathComponent("shelf")
            try write(author, source.appendingPathComponent("i18n/fr.json"))
            try write(local, destination.appendingPathComponent("i18n/fr.json"))
            #expect(TranslationUpdate.comparisons(source: source, installed: destination).keys.sorted() == ["i18n/fr.json"])

            try TranslationUpdate.apply(choice, relativePaths: ["i18n/fr.json"], source: source,
                                        destination: destination, discardedRoot: shelf)
            let result = try I18nLenientParser.parse(try read(destination.appendingPathComponent("i18n/fr.json")))
            switch choice {
            case .keepLocal:
                #expect(result["farewell"] == "Au revoir local" && result["thanks"] == nil)
                #expect(try read(shelf.appendingPathComponent("i18n/fr.json")) == author)
            case .takeAuthor:
                #expect(result["farewell"] == "Adieu" && result["thanks"] != nil)
            case .merge:
                #expect(result["farewell"] == "Au revoir local" && result["thanks"] == #"Merci "beaucoup""#)
            }
        }
    }

    /// Identiques : rien à proposer ; un seul côté : rien non plus.
    @Test func nothingToOfferWithoutTwoDifferentFiles() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a"), installed = root.appendingPathComponent("b")
        try write(author, source.appendingPathComponent("i18n/fr.json"))
        try write(author, installed.appendingPathComponent("i18n/fr.json"))
        try write(author, source.appendingPathComponent("Sub/i18n/fr.json"))
        #expect(TranslationUpdate.comparisons(source: source, installed: installed).isEmpty)
    }

    @Test func realFolderFollowsThePauseDot() throws {
        let mods = try tempDir()
        defer { try? FileManager.default.removeItem(at: mods) }
        try FileManager.default.createDirectory(at: mods.appendingPathComponent(".Pack/Comp"), withIntermediateDirectories: true)
        #expect(ModFolderPaths.realFolder(modsRoot: mods, logical: "Pack/Comp")?.path.hasSuffix("/.Pack/Comp") == true)
        #expect(ModFolderPaths.realFolder(modsRoot: mods, logical: "Absent") == nil)
    }

    /// Une sélection reconstruite garde le choix (les copieurs `with`).
    @Test func selectionCopiesKeepTheChoice() {
        let selection = InstallSelection(modId: UUID(), selected: true, conflictResolution: .overwriteWithBackup)
            .with(translation: .merge)
        #expect(selection.with(selected: false).translationChoice == .merge)
        #expect(selection.with(resolution: .rename).translationChoice == .merge)
    }
}

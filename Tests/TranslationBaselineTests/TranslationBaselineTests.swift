import Foundation
import Testing
@testable import StarHubTHCore

/// Tâche 10 du plan P2b — le drapeau « écrit sans être relu » sur les
/// références de traduction. Rétrocompatible : les sidecars posés avant la
/// P2b ne portent pas le champ et décodent à `false` (spec §2.4/§3).
struct TranslationBaselineEntryTests {

    @Test func sidecarBeforeP2bDecodesWithReviewNeededFalse() throws {
        let json = #"{"source":"Hello","target":"Bonjour","tokenMismatchAccepted":false}"#
        let entry = try JSONDecoder().decode(TranslationBaseline.Entry.self,
                                             from: Data(json.utf8))
        #expect(entry.reviewNeeded == false)
    }

    @Test func roundTripKeepsReviewNeeded() throws {
        let entry = TranslationBaseline.Entry(source: "Hello", target: "Bonjour",
                                              reviewNeeded: true)
        let data = try JSONEncoder().encode(entry)
        let back = try JSONDecoder().decode(TranslationBaseline.Entry.self, from: data)
        #expect(back.reviewNeeded == true)
    }

    @Test func reviewNeededDefaultsToFalse() {
        let entry = TranslationBaseline.Entry(source: "a", target: "b")
        #expect(entry.reviewNeeded == false)
    }

    @Test func reviewNeededEncodesAsItsOwnField() throws {
        let data = try JSONEncoder().encode(
            TranslationBaseline.Entry(source: "a", target: "b", reviewNeeded: true))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["reviewNeeded"] as? Bool == true)
    }
}

/// Tâche 14 du plan P2b — pose et retrait du drapeau « à relire » dans le
/// magasin, sur des dossiers temporaires : la persistance du lot passe par
/// ces fonctions, pas par une réécriture du magasin à la main côté VM.
struct TranslationBaselineReviewFlagTests {

    private var store: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineReviewFlag-\(UUID().uuidString)")
    }

    @Test func setReviewNeededCreatesTheEntryAndSurvivesReload() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.setReviewNeeded(component: nil, key: "intro",
                                                source: "Hello", target: "Bonjour",
                                                modFolderName: "ModA", in: dir)
        let entries = TranslationBaseline.load(modFolderName: "ModA", in: dir)
        let entry = entries[TranslationBaseline.key(component: nil, key: "intro")]
        #expect(entry?.reviewNeeded == true)
        #expect(entry?.source == "Hello")
        #expect(entry?.target == "Bonjour")
        #expect(TranslationBaseline.reviewNeededRowIDs(modFolderName: "ModA", in: dir)
                == ["intro"])
    }

    @Test func setReviewNeededKeepsTheValuesOfAnExistingEntry() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        // Une référence déjà adoptée — le lot ne touche en pratique que des
        // clés sans référence, mais la fonction ne doit détruire rien de ce
        // qui existe si on l'appelle sur une clé connue.
        var entries = [TranslationBaseline.key(component: "CP", key: "quest"):
                        TranslationBaseline.Entry(source: "Old", target: "Vieux")]
        try TranslationBaseline.save(entries, modFolderName: "ModA", in: dir)
        try TranslationBaseline.setReviewNeeded(component: "CP", key: "quest",
                                                source: "New", target: "Neuf",
                                                modFolderName: "ModA", in: dir)
        entries = TranslationBaseline.load(modFolderName: "ModA", in: dir)
        let entry = entries[TranslationBaseline.key(component: "CP", key: "quest")]
        #expect(entry?.source == "Old")
        #expect(entry?.target == "Vieux")
        #expect(entry?.reviewNeeded == true)
    }

    @Test func clearReviewNeededRemovesTheFlagAndKeepsTheEntry() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.setReviewNeeded(component: nil, key: "intro",
                                                source: "Hello", target: "Bonjour",
                                                modFolderName: "ModA", in: dir)
        try TranslationBaseline.clearReviewNeeded(component: nil, key: "intro",
                                                  modFolderName: "ModA", in: dir)
        let entries = TranslationBaseline.load(modFolderName: "ModA", in: dir)
        let entry = entries[TranslationBaseline.key(component: nil, key: "intro")]
        #expect(entry?.reviewNeeded == false)   // le drapeau seul est parti
        #expect(entry?.source == "Hello")
        #expect(TranslationBaseline.reviewNeededRowIDs(modFolderName: "ModA", in: dir).isEmpty)
    }

    @Test func clearReviewNeededWithoutEntryIsANoOp() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.clearReviewNeeded(component: nil, key: "ghost",
                                                  modFolderName: "ModA", in: dir)
        #expect(TranslationBaseline.load(modFolderName: "ModA", in: dir).isEmpty)
    }

    @Test func rowIDsUseTheDiffRowIdentityFormat() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.setReviewNeeded(component: "CP", key: "quest",
                                                source: "s", target: "t",
                                                modFolderName: "ModA", in: dir)
        try TranslationBaseline.setReviewNeeded(component: nil, key: "intro",
                                                source: "s", target: "t",
                                                modFolderName: "ModA", in: dir)
        #expect(TranslationBaseline.reviewNeededRowIDs(modFolderName: "ModA", in: dir)
                    .sorted() == ["CP/quest", "intro"])
    }
}

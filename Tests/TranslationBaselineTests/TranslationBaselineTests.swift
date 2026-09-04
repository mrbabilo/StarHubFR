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

    /// Le lot pose le drapeau sur des centaines de clés. Une par une, chaque
    /// pose relit **tout** le sidecar et le réécrit : sur un mod à 11 000
    /// clés le coût devient quadratique, sur le thread principal, entre deux
    /// appels réseau. La forme plurielle fait une lecture et une écriture.
    @Test func flaggingManyKeysReadsAndWritesTheSidecarOnce() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.save(
            [TranslationBaseline.key(component: nil, key: "old"):
                TranslationBaseline.Entry(source: "Old", target: "Vieux")],
            modFolderName: "ModA", in: dir)
        try TranslationBaseline.setReviewNeeded(
            [.init(component: nil, key: "a", source: "A", target: "Ah"),
             .init(component: "CP", key: "b", source: "B", target: "Bé")],
            modFolderName: "ModA", in: dir)
        let entries = TranslationBaseline.load(modFolderName: "ModA", in: dir)
        #expect(entries[TranslationBaseline.key(component: nil, key: "a")]?.reviewNeeded == true)
        #expect(entries[TranslationBaseline.key(component: "CP", key: "b")]?.target == "Bé")
        // L'entrée qui n'était pas du lot est intacte, drapeau compris.
        #expect(entries[TranslationBaseline.key(component: nil, key: "old")]
                == TranslationBaseline.Entry(source: "Old", target: "Vieux"))
    }

    /// Même règle que la forme singulière : une entrée existante garde ses
    /// valeurs, le drapeau n'est pas une réévaluation de la référence.
    @Test func flaggingManyKeysKeepsTheValuesOfExistingEntries() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.save(
            [TranslationBaseline.key(component: nil, key: "a"):
                TranslationBaseline.Entry(source: "Old", target: "Vieux",
                                          tokenMismatchAccepted: true)],
            modFolderName: "ModA", in: dir)
        try TranslationBaseline.setReviewNeeded(
            [.init(component: nil, key: "a", source: "New", target: "Neuf")],
            modFolderName: "ModA", in: dir)
        let entry = TranslationBaseline.load(modFolderName: "ModA", in: dir)[
            TranslationBaseline.key(component: nil, key: "a")]
        #expect(entry?.source == "Old")
        #expect(entry?.target == "Vieux")
        #expect(entry?.tokenMismatchAccepted == true)
        #expect(entry?.reviewNeeded == true)
    }

    /// Rien à poser : ni lecture ni écriture, et surtout pas un sidecar créé
    /// pour un lot qui n'a rien traduit.
    @Test func flaggingNothingWritesNoSidecar() throws {
        let dir = store
        defer { try? FileManager.default.removeItem(at: dir) }
        try TranslationBaseline.setReviewNeeded([], modFolderName: "ModA", in: dir)
        #expect(TranslationBaseline.load(modFolderName: "ModA", in: dir).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
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

    // MARK: - Renommage du dossier (X60)

    /// Le magasin de référence d'un mod et son entrée d'index sont tous deux
    /// indexés sur le nom de dossier. Renommer sans les emmener ferait
    /// réapparaître un compte de clés obsolètes sous l'ancien nom — et le mod
    /// renommé repartirait de zéro, sa référence perdue.
    @Test func renamingCarriesTheStoreAndTheIndexEntry() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-rename-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = TranslationBaseline.Entry(source: "Hello", target: "Bonjour")
        try TranslationBaseline.save(["clé": entry], modFolderName: "Seaside", in: dir)
        try TranslationBaseline.updateIndex(modFolderName: "Seaside", outdatedCount: 3, in: dir)

        try TranslationBaseline.rename(modFolderName: "Seaside", to: "Seaside (Liana)", in: dir)

        #expect(TranslationBaseline.loadIndex(in: dir) == ["Seaside (Liana)": 3])
        #expect(TranslationBaseline.load(modFolderName: "Seaside (Liana)", in: dir)["clé"]?.source == "Hello")
        #expect(TranslationBaseline.load(modFolderName: "Seaside", in: dir).isEmpty)
    }

    /// Un mod sans référence enregistrée ne fait rien échouer.
    @Test func renamingAModWithoutABaselineIsHarmless() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-rename-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try TranslationBaseline.rename(modFolderName: "Inconnu", to: "Autre", in: dir)
        #expect(TranslationBaseline.loadIndex(in: dir).isEmpty)
    }
}

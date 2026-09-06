import Testing
import Foundation
@testable import StarHubTHCore

/// R2 — le store du journal d'application de profil. `storageDirectory` est
/// global et mutable : la suite est sérialisée et chaque test remet le
/// store à zéro, pour ne jamais risquer le vrai journal d'un parc en cours.
@Suite(.serialized)
struct ProfileApplyJournalTests {

    /// Redirige le store vers un dossier temporaire et le remet ensuite.
    private func withTemporaryStorage(_ body: () throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileApplyJournalTests-\(UUID().uuidString)", isDirectory: true)
        ProfileApplyJournalStore.storageDirectory = dir
        defer {
            ProfileApplyJournalStore.storageDirectory = nil
            try? FileManager.default.removeItem(at: dir)
        }
        try body()
    }

    private func sampleJournal() -> ProfileApplyJournal {
        ProfileApplyJournal(profileId: UUID(),
                            profileName: "Bac à sable",
                            startedAt: Date(timeIntervalSince1970: 1_772_000_000),
                            moves: [
                                ProfileApplyPlan.Move(folderName: "SeasideSounds",
                                                      modName: "Seaside Sounds",
                                                      uniqueId: "ampedseas.SeasideSounds",
                                                      source: ".SeasideSounds",
                                                      destination: "SeasideSounds",
                                                      direction: .enable),
                                ProfileApplyPlan.Move(folderName: "SkullCavernElevator",
                                                      modName: "Skull Cavern Elevator",
                                                      uniqueId: "moonslime.SkullCavernElevator",
                                                      source: "SkullCavernElevator",
                                                      destination: ".SkullCavernElevator",
                                                      direction: .disable),
                            ])
    }

    @Test func storeRoundTripPreservesTheJournal() throws {
        try withTemporaryStorage {
            let journal = sampleJournal()
            ProfileApplyJournalStore.save(journal)
            #expect(ProfileApplyJournalStore.load() == journal)
        }
    }

    @Test func clearMakesLoadReturnNil() throws {
        try withTemporaryStorage {
            ProfileApplyJournalStore.save(sampleJournal())
            ProfileApplyJournalStore.clear()
            #expect(ProfileApplyJournalStore.load() == nil)
        }
    }

    @Test func clearWithoutFileIsNotAnError() throws {
        try withTemporaryStorage {
            ProfileApplyJournalStore.clear()
            #expect(ProfileApplyJournalStore.load() == nil)
        }
    }

    @Test func corruptFileLoadsAsNil() throws {
        try withTemporaryStorage {
            // Un journal illisible ne doit jamais paralyser le lancement :
            // il se lit « absent », pas « en échec ».
            let dir = ProfileApplyJournalStore.storageDirectory!
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("{\"profileId\": \"pas un UUID".utf8)
                .write(to: dir.appendingPathComponent("profile_apply_journal.json"))
            #expect(ProfileApplyJournalStore.load() == nil)
        }
    }

    @Test func saveCreatesAMissingDirectory() throws {
        try withTemporaryStorage {
            // Le dossier temporaire n'existe pas encore : `save` doit le
            // créer (le `defaultDirectory()` du patron ne s'exécute qu'une
            // fois — c'est à `save` de garantir le chemin).
            ProfileApplyJournalStore.save(sampleJournal())
            #expect(ProfileApplyJournalStore.load() != nil)
        }
    }
}

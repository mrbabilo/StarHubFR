import Testing
import Foundation
@testable import StarHubTHCore

/// R2 — le store du journal d'application de profil. Son dossier est un
/// **paramètre** : chaque test lui donne le sien, aucun appel ne peut retomber
/// sur le vrai Application Support (il n'y a pas de valeur par défaut, et cette
/// suite ne nomme jamais `AppSupport`), et rien n'est partagé entre tests —
/// d'où la disparition du `.serialized`.
struct ProfileApplyJournalTests {

    /// Un dossier temporaire, nettoyé à la sortie. Volontairement **pas créé**
    /// ici : `saveCreatesAMissingDirectory` compte dessus.
    private func withTemporaryStorage(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileApplyJournalTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
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
        try withTemporaryStorage { dir in
            let journal = sampleJournal()
            ProfileApplyJournalStore.save(journal, in: dir)
            #expect(ProfileApplyJournalStore.load(from: dir) == journal)
        }
    }

    /// **Le test qui épingle la redirection.** Les autres n'observent que
    /// l'aller-retour du store, et resteraient verts si les trois points
    /// d'entrée ignoraient le dossier reçu pour se donner rendez-vous ailleurs
    /// — y compris dans le vrai Application Support. Celui-ci regarde le
    /// disque à l'endroit exact qui a été demandé.
    @Test func theJournalIsWrittenInTheDirectoryItWasGiven() throws {
        try withTemporaryStorage { dir in
            #expect(ProfileApplyJournalStore.save(sampleJournal(), in: dir) == nil)
            let file = dir.appendingPathComponent("profile_apply_journal.json")
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func clearMakesLoadReturnNil() throws {
        try withTemporaryStorage { dir in
            ProfileApplyJournalStore.save(sampleJournal(), in: dir)
            ProfileApplyJournalStore.clear(in: dir)
            #expect(ProfileApplyJournalStore.load(from: dir) == nil)
        }
    }

    @Test func clearWithoutFileIsNotAnError() throws {
        try withTemporaryStorage { dir in
            ProfileApplyJournalStore.clear(in: dir)
            #expect(ProfileApplyJournalStore.load(from: dir) == nil)
        }
    }

    /// Sans dossier de support, l'app ne peut rien persister : le store se tait
    /// (pas d'erreur d'écriture à remonter) et une lecture rend « rien ». C'est
    /// ce que faisait `storageDirectory == nil` — le passage en paramètre le
    /// conserve.
    @Test func noDirectoryMeansNoStorageAndNoCrash() {
        #expect(ProfileApplyJournalStore.save(sampleJournal(), in: nil) == nil)
        #expect(ProfileApplyJournalStore.load(from: nil) == nil)
        ProfileApplyJournalStore.clear(in: nil)
    }

    @Test func corruptFileLoadsAsNil() throws {
        try withTemporaryStorage { dir in
            // Un journal illisible ne doit jamais paralyser le lancement :
            // il se lit « absent », pas « en échec ».
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("{\"profileId\": \"pas un UUID".utf8)
                .write(to: dir.appendingPathComponent("profile_apply_journal.json"))
            #expect(ProfileApplyJournalStore.load(from: dir) == nil)
        }
    }

    @Test func saveCreatesAMissingDirectory() throws {
        try withTemporaryStorage { dir in
            // Le dossier temporaire n'existe pas encore : `save` doit le
            // créer — il est le seul à pouvoir garantir le chemin au moment
            // d'écrire, et à pouvoir signaler son échec.
            #expect(ProfileApplyJournalStore.save(sampleJournal(), in: dir) == nil)
            #expect(ProfileApplyJournalStore.load(from: dir) != nil)
        }
    }
}

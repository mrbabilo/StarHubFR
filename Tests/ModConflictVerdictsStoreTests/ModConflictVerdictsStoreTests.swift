import Testing
import Foundation
@testable import StarHubTHCore

/// ⚠️ Ces tests ne doivent **jamais** toucher
/// `~/Library/Application Support/StarHubTH/mod_conflicts.json` : c'est le
/// fichier réel de l'utilisateur. `load(from:)`/`save(_:to:)` acceptent une
/// `URL` explicite justement pour ça — chaque test travaille dans son propre
/// dossier temporaire, jamais sur le fichier par défaut.
struct ModConflictVerdictsStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_595_034)

    private func tempFileURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModConflictVerdictsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mod_conflicts.json")
    }

    /// **Un fichier absent rend un magasin vide, pas une erreur.** Premier
    /// lancement, ou dossier jamais créé : l'utilisateur doit pouvoir ouvrir le
    /// rapport d'incompatibilités sans que ça plante ni ne lève d'exception.
    @Test func aMissingFileYieldsAnEmptyStore() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let loaded = ModConflictVerdictsStore.load(from: url)
        #expect(loaded == ModConflictVerdicts())
        #expect(loaded.declared.isEmpty)
        #expect(loaded.dismissed.isEmpty)
    }

    /// **L'aller-retour préserve un verdict déclaré et un verdict écarté.**
    /// C'est le cœur du magasin : ce qu'on y met doit en ressortir identique.
    @Test func aRoundTripPreservesADeclaredAndADismissedVerdict() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var verdicts = ModConflictVerdicts()
        verdicts.declare(ModConflictPair("SVE", "[CP] Make Gunther Real"), note: "casse en jeu", at: t0)
        verdicts.dismiss(ModConflictPair("A", "B"), note: "faux positif", at: t0.addingTimeInterval(60))

        #expect(ModConflictVerdictsStore.save(verdicts, to: url) == true)

        let reloaded = ModConflictVerdictsStore.load(from: url)
        #expect(reloaded == verdicts)

        let declared = reloaded.verdict(for: ModConflictPair("SVE", "[CP] Make Gunther Real"))
        #expect(declared?.isDeclared == true)
        #expect(declared?.note == "casse en jeu")

        let dismissed = reloaded.verdict(for: ModConflictPair("A", "B"))
        #expect(dismissed?.isDeclared == false)
        #expect(dismissed?.note == "faux positif")
    }

    /// **Une écriture réussie rend `true`.** L'appelant s'en sert pour décider
    /// s'il doit avertir l'utilisateur — un test qui ne le vérifierait pas
    /// laisserait passer une régression silencieuse sur ce contrat.
    @Test func aSuccessfulSaveReportsTrue() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var verdicts = ModConflictVerdicts()
        verdicts.declare(ModConflictPair("A", "B"), note: "", at: t0)
        #expect(ModConflictVerdictsStore.save(verdicts, to: url) == true)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// **Un dossier parent absent fait échouer l'écriture — et le magasin le
    /// dit.** `save` ne crée pas de dossier intermédiaire pour une URL fournie
    /// explicitement (seul `directory`, le chemin par défaut, le fait) : un
    /// appelant qui pointe vers un chemin inexistant doit recevoir `false`, pas
    /// un déni silencieux.
    @Test func savingToAnUnreachablePathReportsFalse() throws {
        let unreachable = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModConflictVerdictsStoreTests-missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nested/mod_conflicts.json")
        var verdicts = ModConflictVerdicts()
        verdicts.declare(ModConflictPair("A", "B"), note: "", at: t0)
        #expect(ModConflictVerdictsStore.save(verdicts, to: unreachable) == false)
    }
}

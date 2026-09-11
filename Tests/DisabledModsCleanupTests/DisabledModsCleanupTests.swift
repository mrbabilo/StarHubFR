import Foundation
import Testing
@testable import StarHubTHCore

/// Ce que « Vider les mods désactivés » supprime — **définitivement**, pas à
/// la corbeille.
///
/// Le tri n'était pas vérifiable, et l'enjeu n'est pas théorique : sur le parc
/// de référence, **721 dossiers** sont en pause (mesuré le 2026-09-11) et
/// partiraient tous. Un résidu système pris pour un mod, ou l'inverse, se
/// paie ici sans retour possible.
struct DisabledModsCleanupTests {

    @Test func aPausedModIsATarget() {
        #expect(DisabledModsCleanup.targets(in: [".SVE"]) == [".SVE"])
    }

    @Test func anActiveModIsNeverTouched() {
        // Seules les entrées pointées sont des mods en pause. Supprimer un
        // dossier actif viderait la modlist.
        #expect(DisabledModsCleanup.targets(in: ["SVE", "Content Patcher"]).isEmpty)
    }

    @Test func systemLeftoversAreSpared() {
        // Le scan traite tout dossier commençant par un point comme un mod en
        // pause : sans cette garde, `.Spotlight-V100` et `.Trashes` — des
        // dossiers du système — seraient supprimés par un bouton qui promet
        // de ne toucher qu'à des mods.
        #expect(DisabledModsCleanup.targets(in: [".DS_Store", ".Spotlight-V100", ".Trashes"])
                .isEmpty)
    }

    @Test func appleDoubleForksAreSpared() {
        #expect(DisabledModsCleanup.targets(in: ["._SVE"]).isEmpty)
    }

    @Test func theOrderOfTheFolderIsKept() {
        // Le résultat sert à supprimer, pas à afficher : il n'a pas à
        // réordonner, mais il ne doit rien perdre non plus.
        #expect(DisabledModsCleanup.targets(in: [".B", "A", ".C", ".DS_Store"]) == [".B", ".C"])
    }

    // MARK: - Ce qu'on dit une fois la passe faite

    @Test func nothingFoundIsSaidApartFromASuccess() {
        // « Supprimés avec succès » sur zéro dossier ferait croire que le
        // ménage a eu lieu.
        #expect(DisabledModsCleanup.outcome(removed: 0, failed: 0) == .nothingFound)
    }

    @Test func aCleanPassIsASuccess() {
        #expect(DisabledModsCleanup.outcome(removed: 12, failed: 0) == .removed(12))
    }

    @Test func anyFailureIsReportedEvenWhenMostSucceeded() {
        // Le compte des réussites ne doit pas masquer qu'un dossier est resté :
        // l'utilisateur croirait son `Mods/` propre.
        #expect(DisabledModsCleanup.outcome(removed: 12, failed: 1) == .partial(removed: 12,
                                                                               failed: 1))
    }

    @Test func aTotalFailureIsNotSilentEither() {
        #expect(DisabledModsCleanup.outcome(removed: 0, failed: 3) == .partial(removed: 0,
                                                                              failed: 3))
    }

    @Test func aPassThatTouchedNothingDoesNotAskForARescan() {
        // Rescaner un parc inchangé coûte plusieurs secondes sur ~900 mods.
        #expect(!DisabledModsCleanup.outcome(removed: 0, failed: 0).needsRescan)
    }

    @Test func aPassThatFailedStillAsksForARescan() {
        // Un échec partiel a pu déplacer des dossiers : l'écran doit refléter
        // le disque, quel qu'il soit.
        #expect(DisabledModsCleanup.outcome(removed: 0, failed: 1).needsRescan)
    }
}

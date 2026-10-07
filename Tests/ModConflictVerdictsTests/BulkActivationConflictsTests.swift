import Testing
import Foundation
@testable import StarHubTHCore

/// A5-T8 — un geste groupé (« Tout activer », bandeau de sélection, profil)
/// annonce les paires en conflit qu'il **rendrait** actives, jamais celles qui
/// l'étaient déjà, ni celles que l'utilisateur a écartées.
struct BulkActivationConflictsTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_417_600)

    private func mod(_ folder: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: folder.lowercased(), name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], languages: [])
    }

    private func pack(_ folder: String, _ children: [String], enabled: Bool) -> ModItem {
        ModItem(uniqueId: "", name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [],
                children: children.map { mod(folder + "/" + $0, enabled: enabled) },
                isGroup: true)
    }

    /// Le parc du 2026-10-08 : les deux Haley en pause, Leah active d'un côté.
    private var parc: [ModItem] {
        [mod("Miihaus Haley", enabled: false), mod("Nyapu Haley", enabled: false),
         mod("Leah A", enabled: true), mod("Leah B", enabled: false),
         pack("Rasmodia", ["[CP] Rasmodia"], enabled: false)]
    }

    private func newConflicts(_ verdicts: ModConflictVerdicts = ModConflictVerdicts(),
                              candidates: [ModConflictPair],
                              enabling: Set<String>, disabling: Set<String> = [],
                              in mods: [ModItem]? = nil) -> [ModConflictPair] {
        let mods = mods ?? parc
        return verdicts.newConflicts(candidates: candidates,
                                     activeBefore: mods.activeFolders(enabling: [], disabling: []),
                                     activeAfter: mods.activeFolders(enabling: enabling, disabling: disabling),
                                     topFolders: mods.topFolders)
    }

    /// Sans geste, l'état « après » est l'état actuel — composants compris,
    /// en-tête de pack exclu, comme la pastille.
    @Test func activeFoldersWithoutGestureIsTheCurrentState() {
        #expect(parc.activeFolders(enabling: [], disabling: []) == ["Leah A"])
        #expect(parc.activeFolders(enabling: ["Rasmodia"], disabling: ["Leah A"]) == ["Rasmodia/[CP] Rasmodia"])
    }

    /// Le cas qui a motivé l'item : « Tout activer » réveille les deux Haley
    /// **ensemble**. Aucun n'est actif avant — la garde unitaire, qui ne
    /// regarde que les mods déjà actifs, n'aurait rien dit.
    @Test func twoModsWokenTogetherAreReported() {
        let pair = ModConflictPair("Miihaus Haley", "Nyapu Haley")
        #expect(newConflicts(candidates: [pair], enabling: ["Miihaus Haley", "Nyapu Haley"]) == [pair])
    }

    @Test func wakingOneSideAgainstAnActiveModIsReported() {
        let pair = ModConflictPair("Leah A", "Leah B")
        #expect(newConflicts(candidates: [pair], enabling: ["Leah B"]) == [pair])
    }

    /// Un composant de pack porte la paire : activer l'en-tête suffit.
    @Test func aPackComponentIsReportedThroughItsHeader() {
        let pair = ModConflictPair("Rasmodia/[CP] Rasmodia", "Leah A")
        #expect(newConflicts(candidates: [pair], enabling: ["Rasmodia"]) == [pair])
    }

    /// Une paire déjà active ne naît pas du geste : la pastille la porte.
    @Test func anAlreadyLivePairStaysSilent() {
        let mods = [mod("A", enabled: true), mod("B", enabled: true), mod("C", enabled: false)]
        #expect(newConflicts(candidates: [ModConflictPair("A", "B")], enabling: ["C"], in: mods).isEmpty)
    }

    @Test func aDismissedPairStaysSilent() {
        var verdicts = ModConflictVerdicts()
        let pair = ModConflictPair("Miihaus Haley", "Nyapu Haley")
        verdicts.dismiss(pair, note: "", at: t0)
        #expect(newConflicts(verdicts, candidates: [pair], enabling: ["Miihaus Haley", "Nyapu Haley"]).isEmpty)
    }

    /// Un profil qui active un côté et met l'autre en pause ne crée rien.
    @Test func pausingTheOtherSideInTheSameGestureStaysSilent() {
        let pair = ModConflictPair("Leah A", "Leah B")
        #expect(newConflicts(candidates: [pair], enabling: ["Leah B"], disabling: ["Leah A"]).isEmpty)
    }

    /// Deux composants du même pack : affaire de l'auteur, pas un arbitrage
    /// — même règle que la garde unitaire (`activationConflict`).
    @Test func componentsOfOnePackStaySilent() {
        let mods = [pack("SVE", ["Farm", "Town"], enabled: false)]
        let candidates = [ModConflictPair("SVE/Farm", "SVE/Town"), ModConflictPair("SVE/Farm", "SVE/Farm")]
        #expect(newConflicts(candidates: candidates, enabling: ["SVE"], in: mods).isEmpty)
    }

    /// Une paire déclarée **et** prévue n'est annoncée qu'une fois, dans un
    /// ordre stable.
    @Test func pairsAreUniqueAndSorted() {
        let haley = ModConflictPair("Miihaus Haley", "Nyapu Haley")
        let leah = ModConflictPair("Leah A", "Leah B")
        #expect(newConflicts(candidates: [haley, leah, haley],
                             enabling: ["Miihaus Haley", "Nyapu Haley", "Leah B"]) == [leah, haley])
    }
}

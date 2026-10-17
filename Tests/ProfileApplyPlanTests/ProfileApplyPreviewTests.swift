import Foundation
import Testing
@testable import StarHubTHCore

/// P5-1 — l'aperçu d'un profil annonce exactement ce que son activation
/// ferait : les dossiers de tête du plan, triés, et les conflits que la garde
/// opposera.
struct ProfileApplyPreviewTests {

    private func mod(_ folder: String, id: String? = nil, enabled: Bool,
                     children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: id ?? (children == nil ? folder.lowercased() : ""), name: folder, folderName: folder,
                version: "1.0", author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], children: children, isGroup: children != nil)
    }

    private func preview(_ ids: [String], _ mods: [ModItem],
                         candidates: [ModConflictPair] = []) -> ProfileApplyPreview {
        ProfileApplyPreview.make(applying: ModProfile(name: "P", enabledModIds: ids), to: mods,
                                 verdicts: ModConflictVerdicts(), candidates: candidates)
    }

    /// Les deux listes sont triées par nom, sans tenir compte de la casse ni
    /// de l'ordre du scan.
    @Test func movesAreSplitAndSortedByName() {
        let result = preview(["zeta", "alpha"], [
            mod("Zeta", enabled: false), mod("beta", enabled: true),
            mod("Alpha", enabled: false), mod("Gamma", enabled: true),
        ])
        #expect(result.toEnable.map(\.folderName) == ["Alpha", "Zeta"])
        #expect(result.toDisable.map(\.folderName) == ["beta", "Gamma"])
    }

    /// Un pack dont le profil ne réclame qu'un composant bouge en entier : un
    /// seul dossier, celui de tête. Les mods de SMAPI ne partent jamais en
    /// pause, même absents du profil.
    @Test func aPackMovesAsOneFolderAndSmapiModsStay() {
        let pack = mod("SVE", enabled: false, children: [
            mod("SVE/[CP] SVE", id: "flashshifter.sve", enabled: false),
            mod("SVE/[FTM] SVE", id: "flashshifter.svecode", enabled: false),
        ])
        let result = preview(["FlashShifter.SVE"], [
            pack, mod("SaveBackup", id: "SMAPI.SaveBackup", enabled: true),
        ])
        #expect(result.toEnable.map(\.folderName) == ["SVE"])
        #expect(result.toDisable.isEmpty)
    }

    /// Les conflits sont ceux du plan : deux mods qu'il réveille ensemble.
    /// Une paire dont un membre part en pause ne compte pas.
    @Test func conflictsFollowThePlan() {
        let woken = ModConflictPair("Haley A", "Haley B")
        let leaving = ModConflictPair("Leah A", "Leah B")
        let result = preview(["haley a", "haley b", "leah b"], [
            mod("Haley A", enabled: false), mod("Haley B", enabled: false),
            mod("Leah A", enabled: true), mod("Leah B", enabled: false),
        ], candidates: [woken, leaving])
        #expect(result.conflicts == [woken])
        #expect(!result.isEmpty)
    }

    /// Le profil déjà appliqué : rien ne bougerait.
    @Test func anAppliedProfileIsEmpty() {
        let result = preview(["a"], [mod("A", enabled: true), mod("B", enabled: false)])
        #expect(result.isEmpty)
        #expect(result.conflicts.isEmpty)
    }
}

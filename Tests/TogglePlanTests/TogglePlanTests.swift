import Foundation
import Testing
@testable import StarHubTHCore

/// Le plan de bascule (REFACTORING §6, domaine Bascule) : rapprochement
/// enfant→dossier de premier niveau, re-dérivation de l'état visé depuis
/// l'instantané du parc, chaînage des dépendances requises, republication
/// en mémoire.
@Suite struct TogglePlanTests {

    private func mod(_ name: String, id: String, enabled: Bool = true,
                     deps: [ModDependency] = [], isGroup: Bool = false,
                     children: [ModItem]? = nil, folderName: String? = nil) -> ModItem {
        ModItem(
            uniqueId: id,
            name: name,
            folderName: folderName ?? name,
            version: "1.0",
            author: "T",
            description: "",
            nexusUrl: "",
            nexusModId: "",
            updateKeys: [],
            isEnabled: enabled,
            dependencies: deps,
            children: children,
            isGroup: isGroup)
    }

    private func dep(_ id: String, required: Bool = true) -> ModDependency {
        ModDependency(uniqueId: id, isRequired: required)
    }

    // MARK: - Amorce

    /// Un composant de pack (`Pack/Enfant`) est ramené à son en-tête —
    /// sinon son bouton « Activer » ne faisait rien, en silence.
    @Test func packChildResolvesToOwningFolder() {
        let child = mod("Swim", id: "swim.core", folderName: "Swim Pack/Swim")
        let pack = mod("Swim Pack", id: "swim.pack", isGroup: true, children: [child])
        let plan = TogglePlan.make(mod: child, mods: [pack], chain: false)
        #expect(plan.seedFolder == "Swim Pack")
        #expect(plan.folders == ["Swim Pack"])
    }

    /// Mod déjà premier niveau : l'amorce reste son propre dossier.
    @Test func topLevelModIsItsOwnSeed() {
        let mod = mod("Cheats", id: "cjb.cheats", folderName: "CheatsMenu")
        let plan = TogglePlan.make(mod: mod, mods: [mod], chain: false)
        #expect(plan.seedFolder == "CheatsMenu")
    }

    // MARK: - État visé

    /// L'état visé se re-dérive de l'instantané, pas du `mod` capturé :
    /// un appel empilé peut décrire un mod déjà basculé entre-temps.
    @Test func targetStateDerivesFromSnapshot() {
        let captured = mod("Cheats", id: "cjb.cheats", enabled: false, folderName: "CheatsMenu")
        let snapshot = [mod("Cheats", id: "cjb.cheats", enabled: true, folderName: "CheatsMenu")]
        let plan = TogglePlan.make(mod: captured, mods: snapshot, chain: false)
        #expect(plan.targetState == false)
    }

    // MARK: - Chaînage

    /// Activer : les dépendances requises manquantes ou en pause, deux
    /// niveaux de profondeur ; une dépendance déjà active est traversée
    /// sans être ajoutée — mais ce qui pend en dessous d'elle est rattrapé.
    @Test func enableChainWalksThroughEnabledDeps() {
        let c = mod("C", id: "dep.c", enabled: false, folderName: "C")
        let d = mod("D", id: "dep.d", deps: [dep("dep.c")])
        let e = mod("E", id: "dep.e", enabled: false, folderName: "E")
        let d2 = mod("D2", id: "dep.d2", enabled: false, deps: [dep("dep.e")], folderName: "D2")
        // D est active, requiert C (en pause) ; D2 est en pause, requiert E
        // (en pause). A requiert D puis D2.
        let dEnabled = mod("D", id: "dep.d", deps: [dep("dep.c"), dep("dep.e")])
        let a = mod("A", id: "mod.a", enabled: false, deps: [dep("dep.d"), dep("dep.d2")], folderName: "A")
        let mods = [a, dEnabled, c, e, d2]
        let plan = TogglePlan.make(mod: a, mods: mods, chain: true)
        #expect(plan.folders == ["A", "C", "E", "D2"])
    }

    /// Une dépendance optionnelle en pause n'est pas chaînée.
    @Test func enableChainIgnoresOptional() {
        let a = mod("A", id: "mod.a", enabled: false, deps: [dep("opt.dep", required: false)])
        let o = mod("O", id: "opt.dep", enabled: false, folderName: "O")
        let plan = TogglePlan.make(mod: a, mods: [a, o], chain: true)
        #expect(plan.folders == ["A"])
    }

    /// Mettre en pause : les mods **actifs** qui exigent l'amorce, avec
    /// pli de casse sur l'UniqueID fourni ; un dépendant déjà en pause
    /// n'est pas ajouté.
    @Test func disableChainAddsEnabledDependentsOnly() {
        let target = mod("Lib", id: "lib.core", enabled: true, folderName: "Lib")
        let dependent = mod("App", id: "app.main", enabled: true, deps: [dep("LIB.CORE")], folderName: "App")
        let pausedDependent = mod("Old", id: "old.main", enabled: false, deps: [dep("lib.core")], folderName: "Old")
        let plan = TogglePlan.make(mod: target, mods: [target, dependent, pausedDependent], chain: true)
        #expect(plan.targetState == false)
        #expect(plan.folders == ["Lib", "App"])
    }

    /// Chaînage désactivé : un seul dossier.
    @Test func chainFalseTogglesSeedOnly() {
        let target = mod("Lib", id: "lib.core", enabled: true, folderName: "Lib")
        let dependent = mod("App", id: "app.main", enabled: true, deps: [dep("lib.core")], folderName: "App")
        let plan = TogglePlan.make(mod: target, mods: [target, dependent], chain: false)
        #expect(plan.folders == ["Lib"])
    }

    // MARK: - Republication en mémoire

    /// Seuls les dossiers du plan basculent, et les enfants d'un pack
    /// suivent leur en-tête.
    @Test func flippedTogglesListedFoldersAndPackChildren() {
        let pack = mod("Pack", id: "", enabled: true, isGroup: true,
                       children: [mod("P1", id: "p.1", enabled: true, folderName: "Pack/P1"),
                                  mod("P2", id: "p.2", enabled: true, folderName: "Pack/P2")],
                       folderName: "Pack")
        let untouched = mod("Other", id: "other", enabled: true, folderName: "Other")
        let flipped = TogglePlan.flipped([pack, untouched], folders: ["Pack"], target: false)
        #expect(flipped[0].isEnabled == false)
        #expect(flipped[0].children?.allSatisfy { !$0.isEnabled } == true)
        #expect(flipped[1].isEnabled == true)
    }
}

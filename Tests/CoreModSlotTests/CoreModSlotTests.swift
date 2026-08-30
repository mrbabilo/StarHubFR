import Foundation
import Testing
@testable import StarHubTHCore

/// L'accueil annonce l'état des extensions de base. Plusieurs mods peuvent
/// porter le même mot dans leur nom — le mod lui-même, un pack qui l'étend, une
/// traduction — et désigner le mauvais fait annoncer « actif » pendant que le
/// vrai est en pause.
struct CoreModSlotTests {
    private func mod(_ name: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: name, version: "1",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    @Test func nothingMatchingMeansNotInstalled() {
        let slot = CoreModSlot.resolve(keyword: "content patcher", among: [mod("Automate")])
        #expect(slot.status == .notInstalled)
        #expect(slot.mod == nil)
    }

    @Test func theExactNameWinsOverALongerOneEvenIfBothAreEnabled() {
        let mods = [mod("Content Patcher Animations"), mod("Content Patcher")]
        let slot = CoreModSlot.resolve(keyword: "content patcher", among: mods)
        #expect(slot.mod?.name == "Content Patcher")
        #expect(slot.status == .enabledAndInstalled)
    }

    @Test func anEnabledApproximationBeatsAPausedExactName() {
        // Quelque chose tourne : l'accueil doit le dire, plutôt que de désigner
        // le mod exact qui, lui, ne tourne pas.
        let mods = [mod("Content Patcher", enabled: false), mod("Content Patcher FR")]
        let slot = CoreModSlot.resolve(keyword: "content patcher", among: mods)
        #expect(slot.mod?.name == "Content Patcher FR")
        #expect(slot.status == .enabledAndInstalled)
    }

    @Test func aPausedExactNameIsReportedAsInstalledButDisabled() {
        let slot = CoreModSlot.resolve(keyword: "content patcher",
                                       among: [mod("Content Patcher", enabled: false)])
        #expect(slot.status == .installedButDisabled)
        #expect(slot.mod?.name == "Content Patcher")
    }

    @Test func withNoBetterCandidateTheFirstMatchIsUsed() {
        let mods = [mod("Content Patcher Extras", enabled: false),
                    mod("Content Patcher Animations", enabled: false)]
        let slot = CoreModSlot.resolve(keyword: "content patcher", among: mods)
        #expect(slot.mod?.name == "Content Patcher Extras")
        #expect(slot.status == .installedButDisabled)
    }

    /// **La date d'installation d'un pack.** Un en-tête de groupe est fabriqué
    /// sans `installedFileDate` (`StarHubTHViewModel.swift:2738`) : lu tel
    /// quel, il laissait son créneau de date vide dans la rangée, quand ses
    /// voisins mods seuls en montraient une — la ligne d'un pack paraissait
    /// désalignée. La règle existait déjà en deux exemplaires (le tri de la
    /// liste, le ViewModel) ; elle vit ici, en un seul.
    @Test func aPackInheritsTheMostRecentChildInstallDate() {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 9_000)
        func dated(_ name: String, _ date: Date?) -> ModItem {
            var m = ModItem(uniqueId: "id.\(name)", name: name, folderName: name,
                            version: "1.0", author: "A", description: "",
                            nexusUrl: "", nexusModId: "", isEnabled: true,
                            dependencies: [])
            m.installedFileDate = date
            return m
        }
        var pack = ModItem(uniqueId: "", name: "Pack", folderName: "Pack",
                           version: "", author: "Group", description: "",
                           nexusUrl: "", nexusModId: "", isEnabled: true,
                           dependencies: [],
                           children: [dated("A", old), dated("B", recent), dated("C", nil)],
                           isGroup: true)
        #expect(pack.effectiveInstallDate == recent)
        // La date propre l'emporte quand elle existe.
        pack.installedFileDate = old
        #expect(pack.effectiveInstallDate == old)
        // Un mod seul n'a que la sienne ; sans enfants datés, rien à hériter.
        #expect(dated("Seul", recent).effectiveInstallDate == recent)
        #expect(dated("Muet", nil).effectiveInstallDate == nil)
    }
}

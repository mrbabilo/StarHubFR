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
}

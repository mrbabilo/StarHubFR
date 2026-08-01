import Testing
import Foundation
@testable import StarHubTHCore

/// Déplier les packs était réécrit 22 fois dans 10 fichiers, sous des formes
/// voisines. Une seule définition, et des tests sur les cas qui les faisaient
/// diverger : l'en-tête de pack sans identifiant, l'enfant désactivé, le pack
/// vide.
struct ModItemFlatteningTests {
    private func mod(_ name: String, id: String = "", enabled: Bool = true,
                     children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: id.isEmpty && children == nil ? "id.\(name)" : id,
                name: name, folderName: name, version: "1", author: "", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: enabled, dependencies: [],
                children: children, isGroup: children != nil)
    }

    @Test func aPackIsReplacedByItsComponents() {
        let pack = mod("RSV", children: [mod("Core"), mod("Extras")])
        #expect([pack].flattenedMods.map(\.name) == ["Core", "Extras"])
    }

    @Test func aStandaloneModStandsForItself() {
        #expect([mod("Automate")].flattenedMods.map(\.name) == ["Automate"])
    }

    @Test func aPackHeaderCarriesNoIdentifierOfItsOwn() {
        // L'en-tête est construit avec un uniqueId vide : le compter donnerait
        // une identité partagée par tous les packs.
        let pack = mod("RSV", children: [mod("Core")])
        #expect([pack].allUniqueIds == ["id.Core"])
    }

    @Test func onlyEnabledComponentsAreCaptured() {
        let pack = mod("RSV", children: [mod("Core"), mod("Extras", enabled: false)])
        #expect([pack].enabledUniqueIds == ["id.Core"])
    }

    @Test func aDisabledStandaloneModIsNotCaptured() {
        #expect([mod("Automate", enabled: false)].enabledUniqueIds.isEmpty)
    }

    @Test func allIdentifiersIncludeDisabledOnes() {
        // Sert à dire qu'un profil réclame un mod encore installé mais en pause.
        let pack = mod("RSV", children: [mod("Core"), mod("Extras", enabled: false)])
        #expect([pack].allUniqueIds == ["id.Core", "id.Extras"])
    }

    @Test func anEmptyPackYieldsNothing() {
        #expect([mod("Vide", children: [])].flattenedMods.isEmpty)
    }
}

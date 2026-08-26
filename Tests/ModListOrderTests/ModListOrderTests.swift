import Testing
import Foundation
@testable import StarHubTHCore

/// L'ordre de la liste des mods, demandé le 2026-08-26 : **alphabétique
/// unique**, packs et mods simples mêlés. Le tri d'origine (`scanMods`) faisait
/// passer tous les packs en tête, puis les mods simples — chercher un nom dans
/// la liste dépendait donc de la nature du mod, pas de l'alphabet.
struct ModListOrderTests {

    private func mod(_ name: String, children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: children == nil ? "id.\(name)" : "",
                name: name, folderName: name, version: "1", author: "",
                description: "", nexusUrl: "", nexusModId: "",
                isEnabled: true, dependencies: [],
                children: children, isGroup: children != nil)
    }

    @Test func packsAreNotMovedToTheTop() {
        let mods = [mod("Zebra Pack", children: [mod("Z1")]),
                    mod("Apple"), mod("Banana")]
        #expect(mods.alphabeticalListOrder.map(\.name) == ["Apple", "Banana", "Zebra Pack"])
    }

    @Test func aPackSitsBetweenSimpleMods() {
        // Le cas même du retour utilisateur : un pack « M » entre deux mods
        // simples « A » et « O » — pas relégué dans le bloc des packs.
        let mods = [mod("Alpha"), mod("Midpack", children: [mod("M1")]), mod("Omega")]
        #expect(mods.alphabeticalListOrder.map(\.name) == ["Alpha", "Midpack", "Omega"])
    }

    @Test func comparisonIgnoresCase() {
        let mods = [mod("banana"), mod("Apple")]
        #expect(mods.alphabeticalListOrder.map(\.name) == ["Apple", "banana"])
    }
}

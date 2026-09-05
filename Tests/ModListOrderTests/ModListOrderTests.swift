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

    // MARK: - X73 — la comparaison est celle de macOS, pas celle des scalaires

    @Test func punctuationAndDigitsOrderLikeMacOSNotLikeUnicodeScalars() {
        // Les trois cas relevés sur le parc, ordres **mesurés** avec le vrai
        // comparateur. Comparés octet à octet, `*` (U+002A) et les chiffres
        // passent avant `[` (U+005B) ; macOS range dans l'autre sens.
        #expect([mod("*SorryLabCore*"), mod("[AHM] Mizu's Horse")]
            .alphabeticalListOrder.map(\.name)
            == ["[AHM] Mizu's Horse", "*SorryLabCore*"])
        #expect([mod("[CP] 6480's Storage Variety"), mod("[CP] [DDF] Garry")]
            .alphabeticalListOrder.map(\.name)
            == ["[CP] [DDF] Garry", "[CP] 6480's Storage Variety"])
    }

    @Test func anApostropheDoesNotSeparateTwoModsOfTheSameAuthor() {
        // Le cas le plus lisible du parc : deux mods du même auteur que
        // l'apostrophe et le tiret séparaient. `'` (U+0027) précède `-`
        // (U+002D) en scalaires ; macOS lit les lettres d'abord.
        let mods = [mod("Nyapu's Portraits inspired by Dong"),
                    mod("Nyapu-Style More Haley Events")]
        #expect(mods.alphabeticalListOrder.map(\.name)
            == ["Nyapu-Style More Haley Events", "Nyapu's Portraits inspired by Dong"])
    }

    @Test func theAscendingOrderIsTheMirrorOfTheDescendingOne() {
        // Les deux sens du tri par nom doivent être exactement inverses. Ils
        // ne l'étaient pas : « Nom (Z→A) » comparait déjà comme macOS quand
        // « Nom (A→Z) » héritait de l'ordre par scalaires posé au balayage —
        // 190 des 951 noms du parc changeaient de place entre les deux.
        let names = ["Cabin", "[CP] Bar", "*SorryLabCore*", "6480's Giant Crops",
                     "Nyapu-Style More Haley Events", "Nyapu's Portraits inspired by Dong"]
        let mods = names.map { mod($0) }
        let ascending = mods.alphabeticalListOrder.map(\.name)
        let descending = mods
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
            .map(\.name)
        #expect(ascending == descending.reversed())
    }
}

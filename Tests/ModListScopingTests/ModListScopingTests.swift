import Testing
import Foundation
@testable import StarHubTHCore

/// La règle de cadrage décide de ce que la liste montre **et** de ce sur quoi
/// « Tout activer » agit (X57) : une divergence entre les deux fait basculer des
/// mods que l'utilisateur ne regardait pas. Elle vivait hors du module testable,
/// sans un seul test, sur 949 dossiers.
///
/// Ce qui est éprouvé ici, ce sont les cas qui font diverger deux pipelines
/// jumeaux : le pack et ses composants, le filtre inactif, le premier niveau.
struct ModListScopingTests {

    private func mod(_ name: String, id: String? = nil, config: Bool = false,
                     languages: [String] = [], children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: id ?? (children == nil ? "id.\(name)" : ""),
                name: name, folderName: name, version: "1.0", author: "", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: true, dependencies: [],
                children: children, isGroup: children != nil,
                hasConfigFile: config, languages: languages)
    }

    private func filters(search: String = "", configOnly: Bool = false,
                         favoritesOnly: Bool = false,
                         blacklistedOnly: Bool = false) -> ModListFilters {
        var f = ModListFilters()
        f.search = search
        f.configOnly = configOnly
        f.favoritesOnly = favoritesOnly
        f.blacklistedOnly = blacklistedOnly
        return f
    }

    // MARK: - matchesSelfOrAnyChild

    @Test func aStandaloneModIsTestedOnItself() {
        #expect(ModListScoping.matchesSelfOrAnyChild(mod("Automate")) { $0.name == "Automate" })
        #expect(!ModListScoping.matchesSelfOrAnyChild(mod("Automate")) { $0.name == "Autre" })
    }

    @Test func aPackMatchesThroughAnyOfItsComponents() {
        let pack = mod("RSV", children: [mod("Core"), mod("Extras")])
        #expect(ModListScoping.matchesSelfOrAnyChild(pack) { $0.name == "Extras" })
    }

    @Test func aPackWithNoMatchingComponentDoesNotMatch() {
        let pack = mod("RSV", children: [mod("Core")])
        #expect(!ModListScoping.matchesSelfOrAnyChild(pack) { $0.name == "Absent" })
    }

    @Test func theHeaderItselfIsTestedBeforeItsComponents() {
        // Un en-tête de pack a `dependencies`/`uniqueId` vides : l'éprouver
        // d'abord est toujours sûr, et le plus souvent sans effet — mais quand
        // c'est lui qui porte le nom cherché, il doit répondre.
        let pack = mod("RSV", children: [mod("Core")])
        #expect(ModListScoping.matchesSelfOrAnyChild(pack) { $0.name == "RSV" })
    }

    @Test func anEmptyPackMatchesNothingButItself() {
        let empty = ModItem(uniqueId: "", name: "Vide", folderName: "Vide", version: "",
                            author: "", description: "", nexusUrl: "", nexusModId: "",
                            isEnabled: true, dependencies: [], children: nil, isGroup: true)
        #expect(!ModListScoping.matchesSelfOrAnyChild(empty) { $0.name == "Core" })
        #expect(ModListScoping.matchesSelfOrAnyChild(empty) { $0.name == "Vide" })
    }

    // MARK: - Recherche

    @Test func anEmptySearchLetsEveryoneThrough() {
        #expect(ModListScoping.matchesSearch(mod("Automate"), filters: filters()))
    }

    @Test func theSearchIsCaseInsensitive() {
        #expect(ModListScoping.matchesSearch(mod("Automate"), filters: filters(search: "auto")))
    }

    @Test func theSearchAlsoLooksAtTheUniqueId() {
        // C'est par l'identifiant qu'on retrouve un mod dont le nom affiché ne
        // dit rien — le cas des composants de pack, jamais nommés comme leur page.
        let m = mod("ARV- Maximum", id: "jessebot.alwaysraining")
        #expect(ModListScoping.matchesSearch(m, filters: filters(search: "jessebot")))
    }

    @Test func aPackIsFoundByOneOfItsComponentsName() {
        let pack = mod("RSV", children: [mod("SolarionShrine")])
        #expect(ModListScoping.matchesSearch(pack, filters: filters(search: "solarion")))
    }

    @Test func aSearchMatchingNothingRejects() {
        #expect(!ModListScoping.matchesSearch(mod("Automate"), filters: filters(search: "zzz")))
    }

    // MARK: - Configuration

    @Test func theConfigFilterIsInertWhenOff() {
        #expect(ModListScoping.matchesConfig(mod("Sans config"), filters: filters()))
    }

    @Test func theConfigFilterKeepsOnlyModsWithAConfigFile() {
        #expect(ModListScoping.matchesConfig(mod("Automate", config: true),
                                             filters: filters(configOnly: true)))
        #expect(!ModListScoping.matchesConfig(mod("Sans config"),
                                              filters: filters(configOnly: true)))
    }

    @Test func aPackCountsAsConfigurableThroughOneComponent() {
        // C'est la règle utile : on ouvre le pack pour régler le composant.
        let pack = mod("RSV", children: [mod("Core"), mod("Extras", config: true)])
        #expect(ModListScoping.matchesConfig(pack, filters: filters(configOnly: true)))
    }

    // MARK: - Favoris et mods écartés

    @Test func theFavoritesFilterIsInertWhenOff() {
        #expect(ModListScoping.matchesFavorites(mod("Automate"), filters: filters(),
                                                favorites: []))
    }

    @Test func aFavoriteIsMarkedOnTheTopLevelRow() {
        #expect(ModListScoping.matchesFavorites(mod("Automate"),
                                                filters: filters(favoritesOnly: true),
                                                favorites: ["Automate"]))
    }

    @Test func aPackIsNotFavoriteThroughOneOfItsComponents() {
        // Le voisin qui doit être refusé : la marque vit sur la ligne de
        // premier niveau. La remonter d'un composant ferait apparaître des
        // packs entiers qu'on n'a jamais marqués.
        let pack = mod("RSV", children: [mod("Core")])
        #expect(!ModListScoping.matchesFavorites(pack, filters: filters(favoritesOnly: true),
                                                 favorites: ["Core"]))
    }

    @Test func theBlacklistFilterIsInertWhenOff() {
        #expect(ModListScoping.matchesBlacklisted(mod("Automate"), filters: filters(),
                                                  blacklisted: ["Automate"]))
    }

    @Test func theBlacklistFilterKeepsOnlyDiscardedMods() {
        #expect(ModListScoping.matchesBlacklisted(mod("Automate"),
                                                  filters: filters(blacklistedOnly: true),
                                                  blacklisted: ["Automate"]))
        #expect(!ModListScoping.matchesBlacklisted(mod("Autre"),
                                                   filters: filters(blacklistedOnly: true),
                                                   blacklisted: ["Automate"]))
    }

    @Test func aPackIsNotDiscardedThroughOneOfItsComponents() {
        let pack = mod("RSV", children: [mod("Core")])
        #expect(!ModListScoping.matchesBlacklisted(pack, filters: filters(blacklistedOnly: true),
                                                   blacklisted: ["Core"]))
    }

    // MARK: - Les marques se lisent sur le nom **logique**

    @Test func aPausedModKeepsItsMarksUnderItsLogicalName() {
        // Un mod en pause vit dans `.X` sur le disque, mais `folderName` reste
        // logique — c'est la clé de tous les magasins persistés. Lire le nom
        // physique ici ferait perdre sa marque à chaque mise en pause.
        var paused = mod("Automate")
        paused.isEnabled = false
        #expect(paused.physicalFolderName == ".Automate")
        #expect(ModListScoping.matchesFavorites(paused, filters: filters(favoritesOnly: true),
                                                favorites: ["Automate"]))
    }
}

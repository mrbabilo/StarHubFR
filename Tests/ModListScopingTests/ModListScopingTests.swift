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

    // MARK: - Cadrage par couverture française

    private func coverage(_ translated: Int, of total: Int) -> TranslationCoverage.Coverage {
        .init(total: total, translated: translated, missing: [], empty: [],
              orphan: [], identicalToSource: [])
    }

    private func state(coverage: [String: TranslationCoverage.Coverage] = [:],
                       stale: Set<String> = [],
                       outdatedKeys: [String: Int] = [:]) -> ModListScoping.TranslationState {
        .init(coverage: coverage, stale: stale, outdatedKeys: outdatedKeys)
    }

    @Test func theTranslationFilterIsInertWhenOff() {
        #expect(ModListScoping.matchesTranslation(mod("Automate"), .off, state: state()))
    }

    @Test func availableKeepsModsShippingAFrenchFile() {
        #expect(ModListScoping.matchesTranslation(mod("Automate", languages: ["en", "fr"]),
                                                  .available, state: state()))
        #expect(!ModListScoping.matchesTranslation(mod("Automate", languages: ["en"]),
                                                   .available, state: state()))
    }

    @Test func aPackShipsFrenchThroughAnyComponent() {
        let pack = mod("RSV", children: [mod("Core", languages: ["en"]),
                                         mod("Extras", languages: ["en", "fr"])])
        #expect(ModListScoping.matchesTranslation(pack, .available, state: state()))
    }

    @Test func partialShowsOnlyModsAlreadyMeasured() {
        // Annoncer « complet » sur un mod qu'on n'a pas encore lu serait faux :
        // la couverture se calcule en tâche de fond. Un mod absent de la carte
        // n'est donc **pas** partiel — c'est un inconnu.
        let m = mod("Automate")
        #expect(!ModListScoping.matchesTranslation(m, .partial, state: state()))
        #expect(ModListScoping.matchesTranslation(
            m, .partial, state: state(coverage: ["Automate": coverage(40, of: 100)])))
    }

    @Test func aFullyTranslatedModIsNotPartial() {
        let m = mod("Automate")
        #expect(!ModListScoping.matchesTranslation(
            m, .partial, state: state(coverage: ["Automate": coverage(100, of: 100)])))
    }

    @Test func aBarelyStartedTranslationCountsAsPartialNotAsMissing() {
        // `displayPercent` ne ramène jamais un début de traduction à 0 : le
        // cadrage doit voir 1 %, pas « rien ».
        let m = mod("Automate")
        #expect(ModListScoping.matchesTranslation(
            m, .partial, state: state(coverage: ["Automate": coverage(1, of: 1000)])))
    }

    @Test func missingIgnoresModsWithNoTranslatableTextAtAll() {
        // Mesuré sur le parc : 397 mods sans français, dont **310 sans le
        // moindre fichier de traduction**. Les y faire figurer rendait 8 fois
        // plus de bruit que de signal.
        #expect(!ModListScoping.matchesTranslation(mod("Sans i18n", languages: []),
                                                   .missing, state: state()))
        #expect(ModListScoping.matchesTranslation(mod("Traduisible", languages: ["en"]),
                                                  .missing, state: state()))
    }

    @Test func missingRejectsAModThatAlreadyHasFrench() {
        #expect(!ModListScoping.matchesTranslation(mod("Automate", languages: ["en", "fr"]),
                                                   .missing, state: state()))
    }

    @Test func aPackIsNotMissingFrenchWhenOneComponentHasIt() {
        // Le voisin qui doit être refusé : un seul composant traduit suffit à
        // sortir le pack de « à traduire ».
        let pack = mod("RSV", children: [mod("Core", languages: ["en"]),
                                         mod("Extras", languages: ["en", "fr"])])
        #expect(!ModListScoping.matchesTranslation(pack, .missing, state: state()))
    }

    @Test func staleReadsBothSignals() {
        // La date, connue de tous les mods dès le scan ; les clés, connues des
        // seuls mods dont on a déjà ouvert le diff. L'un ou l'autre suffit.
        let m = mod("Automate")
        #expect(ModListScoping.matchesTranslation(m, .stale, state: state(stale: ["Automate"])))
        #expect(ModListScoping.matchesTranslation(
            m, .stale, state: state(outdatedKeys: ["Automate": 3])))
        #expect(!ModListScoping.matchesTranslation(m, .stale, state: state()))
    }

    @Test func zeroOutdatedKeysIsNotStale() {
        // Zéro est la valeur par défaut d'un mod jamais diffé : le traiter
        // comme un signal ferait apparaître tout le parc.
        #expect(!ModListScoping.matchesTranslation(mod("Automate"), .stale,
                                                   state: state(outdatedKeys: ["Automate": 0])))
    }

    // MARK: - Clé de type inférée

    @Test func aPackTakesTheTagOfItsLeadComponent() {
        let pack = mod("RSV", children: [mod("Core"), mod("Extras")])
        #expect(ModListScoping.inferredTagKey(for: pack)
            == ModListScoping.inferredTagKey(for: mod("Core")))
    }

    /// F3 (2026-09-12) : la clé d'un pack lit le tag **stocké** de son
    /// composant de tête — pas une ré-inférence sur le nom de l'en-tête. Le
    /// nom du pack (« MonPack ») n'a aucun mot-clé : si l'implémentation
    /// repartait de l'en-tête, ce test verrait « Other » au lieu du tag du
    /// composant de tête.
    @Test func aPackReadsTheStoredTagOfItsLeadComponent() {
        let head = mod("Core")
        let pack = mod("MonPack", children: [head, mod("Extras")])
        #expect(ModListScoping.inferredTagKey(for: pack) == head.inferredTag)
        #expect(ModListScoping.inferredTagKey(for: pack) != "Other")
    }

    @Test func anEmptyPackFallsBackToItself() {
        let empty = ModItem(uniqueId: "", name: "Vide", folderName: "Vide", version: "",
                            author: "", description: "", nexusUrl: "", nexusModId: "",
                            isEnabled: true, dependencies: [], children: nil, isGroup: true)
        // Pas de composant de tête : la clé se lit sur l'en-tête lui-même
        // plutôt que de planter sur un `children!` absent.
        #expect(!ModListScoping.inferredTagKey(for: empty).isEmpty)
    }

    // MARK: - Cadrage par catégorie

    private func categorized(_ map: [String: NexusCategory]) -> (ModItem) -> NexusCategory? {
        { map[$0.folderName] }
    }

    @Test func theCategoryFilterIsInertWhenAll() {
        #expect(ModListScoping.matchesCategory(mod("Automate"), filters: filters(),
                                               category: { _ in nil }))
    }

    @Test func aCategoryScopeKeepsOnlyThatCategory() {
        let cat = NexusCategory.all[0]
        var f = filters(); f.category = .category(cat)
        #expect(ModListScoping.matchesCategory(mod("Automate"), filters: f,
                                               category: categorized(["Automate": cat])))
        #expect(!ModListScoping.matchesCategory(mod("Autre"), filters: f,
                                                category: categorized(["Automate": cat])))
    }

    @Test func anInferredTagOnlyAppliesToUncategorizedMods() {
        // Un mod qui a une vraie catégorie ne tombe jamais dans un seau
        // inféré : les deux se recouvriraient, et le compte du menu mentirait.
        let m = mod("Automate")
        var f = filters(); f.category = .inferredTag(ModListScoping.inferredTagKey(for: m))
        #expect(ModListScoping.matchesCategory(m, filters: f, category: { _ in nil }))
        #expect(!ModListScoping.matchesCategory(m, filters: f,
                                                category: { _ in NexusCategory.all[0] }))
    }

    @Test func uncategorizedMeansNoCategoryAndNoSpecificTag() {
        var f = filters(); f.category = .uncategorized
        let other = mod("zzzz")
        // Le mod ne tombe dans « Sans catégorie » que si son tag inféré est
        // « Other » — sinon il a son propre seau.
        let isOther = ModListScoping.inferredTagKey(for: other) == "Other"
        #expect(ModListScoping.matchesCategory(other, filters: f, category: { _ in nil }) == isOther)
        #expect(!ModListScoping.matchesCategory(other, filters: f,
                                                category: { _ in NexusCategory.all[0] }))
    }

    // MARK: - Composition et cadrage

    @Test func theSixFiltersAreCombinedWithAnd() {
        // Un seul filtre qui refuse suffit : c'est ce qui garantit que la
        // bascule en masse agit sur ce que l'utilisateur regarde (X57).
        let m = mod("Automate", config: true)
        var f = filters(search: "automate", configOnly: true)
        f.favoritesOnly = true
        #expect(!ModListScoping.matches(m, filters: f, inputs: .init()))
        #expect(ModListScoping.matches(m, filters: f, inputs: .init(favorites: ["Automate"])))
    }

    @Test func scopingSplitsOnEnabledState() {
        var paused = mod("Pause"); paused.isEnabled = false
        let all = [mod("Actif"), paused]
        #expect(ModListScoping.scoped(all, scope: .all, hasAnomaly: { _ in false }).count == 2)
        #expect(ModListScoping.scoped(all, scope: .enabled,
                                      hasAnomaly: { _ in false }).map(\.name) == ["Actif"])
        #expect(ModListScoping.scoped(all, scope: .disabled,
                                      hasAnomaly: { _ in false }).map(\.name) == ["Pause"])
    }

    @Test func theIssuesScopeReadsTheAnomalyThroughComponents() {
        let pack = mod("RSV", children: [mod("Core"), mod("Cassé")])
        let scoped = ModListScoping.scoped([pack, mod("Sain")], scope: .issues,
                                           hasAnomaly: { $0.name == "Cassé" })
        #expect(scoped.map(\.name) == ["RSV"])
    }

    @Test func aPausedModWithAnAnomalyStillShowsUnderIssues() {
        // Le voisin qui ne doit **pas** être écarté. La restriction aux mods
        // activés vit chez l'appelant, dans le verdict de dépendance
        // (`hasDependencyIssue`), et ne porte que sur les dépendances : une
        // erreur de journal, un manifest sans identifiant ou une
        // incompatibilité ne cessent pas d'exister parce qu'on a mis le mod en
        // pause. Un garde `isEnabled` posé ici les ferait disparaître en
        // silence de l'onglet censé les réunir.
        var paused = mod("Cassé"); paused.isEnabled = false
        let scoped = ModListScoping.scoped([paused], scope: .issues,
                                           hasAnomaly: { _ in true })
        #expect(scoped.map(\.name) == ["Cassé"])
    }

    @Test func theAllScopeNeverAsksForAnomalies() {
        // La closure est paresseuse à dessein : sous « Tous », le balayage de
        // dépendances ne doit pas avoir lieu du tout.
        final class Counter { var calls = 0 }
        let counter = Counter()
        _ = ModListScoping.scoped([mod("a"), mod("b")], scope: .all,
                                  hasAnomaly: { _ in counter.calls += 1; return false })
        #expect(counter.calls == 0)
    }

    // MARK: - Tri

    private func named(_ names: [String]) -> [ModItem] { names.map { mod($0) } }

    @Test func sortingByNameIsANoOp() {
        // La liste porte déjà l'ordre alphabétique, établi par le scan. Trier à
        // blanc coûtait une passe complète sur 949 mods à chaque frappe.
        let input = named(["Zeta", "Alpha"])
        #expect(ModListScoping.sorted(input, by: .name, inputs: .init()).map(\.name)
            == ["Zeta", "Alpha"])
    }

    @Test func sortingByNameDescendingReverses() {
        #expect(ModListScoping.sorted(named(["Alpha", "Zeta"]), by: .nameDescending,
                                      inputs: .init()).map(\.name) == ["Zeta", "Alpha"])
    }

    @Test func sortingByActivationPutsTheMostRecentFirstAndTheUndatedLast() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let sorted = ModListScoping.sorted(
            named(["Ancien", "Jamais", "Recent"]), by: .activationOrder,
            inputs: .init(activationDates: ["Ancien": t0, "Recent": t1]))
        #expect(sorted.map(\.name) == ["Recent", "Ancien", "Jamais"])
    }

    @Test func equalDatesAreBrokenByNameRatherThanLeftUndetermined() {
        // Déviation assumée : l'original rendait `false` à dates égales, ce qui
        // ne donnait un ordre stable que si `sorted(by:)` l'était — la
        // bibliothèque standard ne le garantit pas.
        let t = Date(timeIntervalSince1970: 1_000)
        let sorted = ModListScoping.sorted(
            named(["Zeta", "Alpha"]), by: .activationOrder,
            inputs: .init(activationDates: ["Zeta": t, "Alpha": t]))
        #expect(sorted.map(\.name) == ["Alpha", "Zeta"])
    }

    @Test func sortingBySizePutsTheHeaviestFirstAndTheUnmeasuredLast() {
        // Les non mesurés sont nombreux par construction : rien n'est mesuré
        // tant que la première passe n'a pas abouti.
        let sizes: [String: Int64] = ["Gros": 900, "Petit": 10]
        let sorted = ModListScoping.sorted(
            named(["Petit", "Inconnu", "Gros"]), by: .size,
            inputs: .init(sizeOnDisk: { sizes[$0.folderName] }))
        #expect(sorted.map(\.name) == ["Gros", "Petit", "Inconnu"])
    }

    @Test func sortingBySizeReadsThePhysicalFolderThroughTheCaller() {
        // Cinq des huit plus gros mods du parc sont en pause : le poids se
        // relève sur le nom physique. La closure vient de l'appelant, donc ce
        // test vérifie que le cadrage ne la court-circuite pas.
        var paused = mod("Enorme"); paused.isEnabled = false
        let sorted = ModListScoping.sorted(
            [mod("Petit"), paused], by: .size,
            inputs: .init(sizeOnDisk: { $0.physicalFolderName == ".Enorme" ? 900 : 10 }))
        #expect(sorted.map(\.name) == ["Enorme", "Petit"])
    }

    @Test func sortingByAuthorFallsBackToTheName() {
        let a = ModItem(uniqueId: "a", name: "Zeta", folderName: "Zeta", version: "1",
                        author: "Pathoschild", description: "", nexusUrl: "", nexusModId: "",
                        isEnabled: true, dependencies: [], children: nil)
        let b = ModItem(uniqueId: "b", name: "Alpha", folderName: "Alpha", version: "1",
                        author: "Pathoschild", description: "", nexusUrl: "", nexusModId: "",
                        isEnabled: true, dependencies: [], children: nil)
        #expect(ModListScoping.sorted([a, b], by: .author, inputs: .init()).map(\.name)
            == ["Alpha", "Zeta"])
    }

    @Test func sortingByVersionPutsTheHighestFirst() {
        let old = ModItem(uniqueId: "a", name: "A", folderName: "A", version: "1.2.0",
                          author: "", description: "", nexusUrl: "", nexusModId: "",
                          isEnabled: true, dependencies: [], children: nil)
        let new = ModItem(uniqueId: "b", name: "B", folderName: "B", version: "1.10.0",
                          author: "", description: "", nexusUrl: "", nexusModId: "",
                          isEnabled: true, dependencies: [], children: nil)
        // 1.10 > 1.2 : la comparaison est sémantique, pas lexicographique.
        #expect(ModListScoping.sorted([old, new], by: .version, inputs: .init()).map(\.name)
            == ["B", "A"])
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

import Testing
@testable import StarHubTHCore

/// L'adaptateur de valeurs : ce qu'une `ModCard` peut servir depuis un mod
/// **installé**, qui n'a ni endossements ni catégorie Nexus servis, ni
/// vignette servie. La carte reste telle quel (spec §6) — c'est son
/// alimentation qui change, et ce fichier est le seul endroit qui le sait.
struct ModGridCardValuesTests {
    /// Le patron de `CoreModSlotTests:9` — l'init public explicite de
    /// `ModItem` (`ModItem.swift:70`).
    private func mod(name: String = "Space Core",
                     author: String = "Lita",
                     version: String = "1.4.2",
                     languages: [String] = ["en"]) -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: name,
                version: version, author: author, description: "",
                nexusUrl: "", nexusModId: "", isEnabled: true, dependencies: [],
                languages: languages)
    }

    /// Un pack : `version: ""`, `author: "Group"` (ViewModel:2738) — la
    /// carte doit agréger depuis les enfants, jamais montrer « v · Group ».
    private func pack(children: [ModItem]) -> ModItem {
        ModItem(uniqueId: "id.pack", name: "Mon Pack", folderName: "Mon Pack",
                version: "", author: "Group", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: true, dependencies: [],
                children: children, isGroup: true,
                languages: Set(children.flatMap { $0.languages }).sorted())
    }

    /// Titre = nom, sous-titre = version • auteur (hiérarchie de la rangée :
    /// nom › version › auteur, spec §6).
    @Test func titleAndSubtitle() {
        let card = ModGridCardValues.card(mod: mod(), versionPrefix: "v%@")
        #expect(card.title == "Space Core")
        #expect(card.subtitle == "v1.4.2 · Lita")
    }

    /// Un auteur vide ou « Unknown » ne laisse pas une puce orpheline en
    /// bout de sous-titre — vide plutôt que « Unknown », comme
    /// `authorLabel` (`ModListView.swift:1279`).
    @Test func anEmptyAuthorYieldsVersionOnly() {
        let card = ModGridCardValues.card(mod: mod(author: "Unknown"),
                                          versionPrefix: "v%@")
        #expect(card.subtitle == "v1.4.2")
    }

    /// **Le cas pack** (relecture critique, Critical) : l'en-tête porte
    /// `version: ""` et `author: "Group"` — des sentinelles, pas des
    /// valeurs. La carte agrège : auteur des enfants quand ils partagent le
    /// même, sinon rien ; version partagée, sinon rien. Jamais « v · Group ».
    @Test func aPackAggregatesFromItsChildren() {
        let pack = self.pack(children: [mod(author: "Lita", version: "2.0"),
                                        mod(name: "Composant", author: "Lita", version: "2.0")])
        let card = ModGridCardValues.card(mod: pack, versionPrefix: "v%@")
        #expect(card.title == "Mon Pack")
        #expect(card.subtitle == "v2.0 · Lita")
    }

    /// Un pack aux auteurs ou versions mêlés ne montre **rien** plutôt qu'un
    /// mensonge — même sémantique que `displayAuthor`/`displayVersion`
    /// (`StarHubTHViewModel.swift:4861/4875`), en pur : le repli « version
    /// Nexus du pack » de `displayVersion` dépend du ViewModel et reste hors
    /// de la carte compacte.
    @Test func aPackWithMixedChildrenShowsNothingRatherThanALie() {
        let mixed = pack(children: [mod(author: "Lita", version: "2.0"),
                                    mod(name: "Composant", author: "Nikki", version: "2.1")])
        let card = ModGridCardValues.card(mod: mixed, versionPrefix: "v%@")
        #expect(card.subtitle == "")
    }

    /// Le seul badge qu'un mod installé peut porter : « FR », quand une de
    /// ses langues servies est le français — même source que le slot FR de
    /// la rangée (`frenchSlot`, `ModListView.swift:1342` : `langs.contains("fr")`).
    /// Un pack hérite de l'union des langues de ses enfants (ViewModel:2748).
    @Test func frenchBadge() {
        #expect(ModGridCardValues.card(mod: mod(languages: ["en", "fr"]),
                                       versionPrefix: "v%@").neutralBadge == "FR")
        #expect(ModGridCardValues.card(mod: mod(languages: ["en"]),
                                       versionPrefix: "v%@").neutralBadge == nil)
        let pack = self.pack(children: [mod(languages: ["en", "fr"])])
        #expect(ModGridCardValues.card(mod: pack, versionPrefix: "v%@").neutralBadge == "FR")
    }

    /// Les nil documentés : un mod installé n'a **pas** de vignette servie
    /// (le `ModDetailCache` n'est pas déroulé pour une grille de 966), pas de
    /// pastille « installé » (tout l'est), pas d'endorsements. Ces champs
    /// sont `nil` **par construction**, pas par oubli de l'appelant. (Pas de
    /// champ `category` : `NexusCategory` vit côté app, hors target Core —
    /// c'est la vue qui passe `category: nil`, avec le même commentaire.)
    @Test func theUnservableFieldsAreNilByConstruction() {
        let card = ModGridCardValues.card(mod: mod(), versionPrefix: "v%@")
        #expect(card.thumbnailURL == nil)
        #expect(card.installedLabel == nil)
        #expect(card.endorsements == nil)
    }
}

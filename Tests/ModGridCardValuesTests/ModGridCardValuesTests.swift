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
                     languages: [String] = ["en"],
                     isEnabled: Bool = true,
                     nexusModId: String = "") -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: name,
                version: version, author: author, description: "",
                nexusUrl: "", nexusModId: nexusModId, isEnabled: isEnabled,
                dependencies: [], languages: languages)
    }

    /// Un pack : `version: ""`, `author: "Group"` (ViewModel:2738) — la
    /// carte doit agréger depuis les enfants, jamais montrer « v · Group ».
    private func pack(children: [ModItem], isEnabled: Bool = true) -> ModItem {
        ModItem(uniqueId: "id.pack", name: "Mon Pack", folderName: "Mon Pack",
                version: "", author: "Group", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: isEnabled,
                dependencies: [],
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

    /// L'état **se lit sur la carte** : actif ou en pause, jamais déduit de
    /// l'absence d'un ornement (P6 — un état ne se code pas par une
    /// présence). C'est la vue qui pose le libellé localisé et la teinte ;
    /// l'adaptateur ne dit que lequel des deux.
    @Test func stateIsAlwaysServed() {
        #expect(ModGridCardValues.card(mod: mod(), versionPrefix: "v%@").state == .active)
        #expect(ModGridCardValues.card(mod: mod(isEnabled: false),
                                       versionPrefix: "v%@").state == .paused)
        #expect(ModGridCardValues.card(mod: pack(children: [mod()], isEnabled: false),
                                       versionPrefix: "v%@").state == .paused)
    }

    /// La vignette vient du cache Nexus déjà sur le disque (769 des 791
    /// entrées en portent une, mesuré sur le parc réel) : la carte la sert
    /// telle quelle. Une URL absente, vide ou illisible laisse le rectangle
    /// gris — la hauteur est réservée, rien ne bouge.
    @Test func thumbnailComesFromTheGivenURL() {
        let served = ModGridCardValues.card(mod: mod(), versionPrefix: "v%@",
                                            pictureURL: "https://x.test/a.png")
        #expect(served.thumbnailURL?.absoluteString == "https://x.test/a.png")
        #expect(ModGridCardValues.card(mod: mod(), versionPrefix: "v%@",
                                       pictureURL: "").thumbnailURL == nil)
        #expect(ModGridCardValues.card(mod: mod(), versionPrefix: "v%@").thumbnailURL == nil)
    }

    /// **L'identifiant qui a droit à une image.** Un pack n'en porte pas :
    /// son en-tête est fabriqué avec `nexusModId: ""` (ViewModel:2738). Le
    /// prendre au premier enfant qui en a un — ce que fait
    /// `resolvedNexusModId` pour la fiche — donnerait à un pack **à plat**
    /// (19 dans le parc réel : des mods sans rapport dans un même dossier)
    /// la capture d'écran de son premier composant. La carte n'accepte donc
    /// que l'identifiant que **tous** les enfants partagent, comme
    /// `sharedValue` pour l'auteur et la version.
    @Test func onlyASharedNexusIdEarnsAPicture() {
        let effective: (ModItem) -> String = { $0.nexusModId }
        // Un mod ordinaire : son propre identifiant.
        #expect(ModGridCardValues.sharedNexusId(of: mod(nexusModId: "1234"),
                                                effectiveId: effective) == "1234")
        // Un vrai pack : un seul mod Nexus, plusieurs dossiers.
        let real = pack(children: [mod(nexusModId: "42"),
                                   mod(name: "Composant", nexusModId: "42")])
        #expect(ModGridCardValues.sharedNexusId(of: real, effectiveId: effective) == "42")
        // Un pack à plat : des mods sans rapport, aucune image légitime.
        let flat = pack(children: [mod(nexusModId: "42"),
                                   mod(name: "Composant", nexusModId: "77")])
        #expect(ModGridCardValues.sharedNexusId(of: flat, effectiveId: effective) == nil)
        // Rien de déclaré : rien à servir.
        #expect(ModGridCardValues.sharedNexusId(of: mod(), effectiveId: effective) == nil)
        #expect(ModGridCardValues.sharedNexusId(of: pack(children: [mod()]),
                                                effectiveId: effective) == nil)
    }

    /// L'identifiant **propre** d'un en-tête l'emporte : c'est celui que
    /// l'utilisateur a saisi à la main pour ce pack (`nexusCustomModIds`,
    /// clé `folderName`), et il vaut mieux que n'importe quelle déduction.
    @Test func anOwnIdWinsOverTheChildren() {
        let flat = pack(children: [mod(nexusModId: "42"),
                                   mod(name: "Composant", nexusModId: "77")])
        let effective: (ModItem) -> String = { $0.isGroup ? "999" : $0.nexusModId }
        #expect(ModGridCardValues.sharedNexusId(of: flat, effectiveId: effective) == "999")
    }

    /// Les nil documentés : un mod installé n'a pas d'endossements servis,
    /// et sa catégorie ne passe pas par ici (`NexusCategory` vit côté app,
    /// hors target Core — c'est la vue qui la résout par `vm.category(for:)`).
    @Test func theUnservableFieldsAreNilByConstruction() {
        let card = ModGridCardValues.card(mod: mod(), versionPrefix: "v%@")
        #expect(card.endorsements == nil)
    }
}

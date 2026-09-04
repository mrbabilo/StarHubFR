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

    // MARK: - Retrouver un mod par son identifiant
    //
    // 296 déclarations de dépendances du parc (109 identifiants distincts)
    // désignent un mod installé **en composant de pack**. Les chercher dans
    // les seules lignes de premier niveau les annonçait manquantes.

    @Test func aComponentOfAPackIsFoundByItsIdentifier() {
        let pack = mod("SVE", id: "", children: [mod("Code", id: "FlashShifter.SVECode"),
                                                 mod("FTM", id: "FlashShifter.SVE-FTM")])
        #expect([pack].mod(withUniqueId: "FlashShifter.SVE-FTM")?.name == "FTM")
    }

    @Test func aStandaloneModIsFoundByItsIdentifier() {
        #expect([mod("Automate", id: "Pathoschild.Automate")]
            .mod(withUniqueId: "Pathoschild.Automate")?.name == "Automate")
    }

    @Test func theSearchIgnoresCaseLikeSmapi() {
        #expect([mod("CP", id: "Pathoschild.ContentPatcher")]
            .mod(withUniqueId: "pathoschild.contentpatcher") != nil)
    }

    @Test func aTopLevelModWinsOverAComponentOfTheSameId() {
        // Cas du parc : un identifiant partagé par un mod autonome et un
        // composant (Swim est installé deux fois). La ligne de premier niveau
        // est celle que l'utilisateur voit — c'est elle qu'on rend.
        let pack = mod("Pack", id: "", children: [mod("Copie", id: "dupe.id")])
        let standalone = mod("Original", id: "dupe.id")
        #expect([standalone, pack].mod(withUniqueId: "dupe.id")?.name == "Original")
    }

    @Test func theTopLevelModWinsEvenWhenThePackComesFirst() {
        // Le test ci-dessus passait quel que soit le code : il donnait au mod
        // de tête la première place du tableau, donc la boucle le rencontrait
        // d'abord. La règle doit tenir **seule**, sans hériter de l'ordre.
        //
        // Cas réel du parc (2026-09-04) : `schulz.SexyCombatIdols` est installé
        // deux fois — en mod de tête `.SexyCombatIdols` (v1.1.1, en pause) et
        // en composant `.SexyCombatIdolsNEW/SexyCombatIdols` (v1.2.0). Lequel
        // des deux est rendu décidait jusqu'ici de l'ordre d'énumération du
        // dossier `Mods/`, qui n'est pas garanti — et c'est ce mod que
        // l'installateur écrase, sauvegarde et dont il ancre la version.
        let pack = mod("Pack", id: "", children: [mod("Copie", id: "dupe.id")])
        let standalone = mod("Original", id: "dupe.id")
        #expect([pack, standalone].mod(withUniqueId: "dupe.id")?.name == "Original")
    }

    @Test func aComponentIsStillFoundWhenNoTopLevelModClaimsTheId() {
        // La préférence pour la tête ne doit pas coûter la recherche dans les
        // packs : 296 déclarations de dépendances du parc en dépendent.
        let pack = mod("Pack", id: "", children: [mod("Composant", id: "only.here")])
        let other = mod("Autre", id: "autre.id")
        #expect([pack, other].mod(withUniqueId: "only.here")?.name == "Composant")
    }

    @Test func anAbsentIdentifierFindsNothing() {
        #expect([mod("Automate", id: "Pathoschild.Automate")]
            .mod(withUniqueId: "Nobody.Here") == nil)
    }

    @Test func anEmptyIdentifierNeverMatchesAPackHeader() {
        // L'en-tête d'un pack porte un `uniqueId` vide, et 111 mods du parc
        // n'en déclarent aucun : chercher "" ne doit pas les apparier.
        let pack = mod("RSV", id: "", children: [mod("Core", id: "")])
        #expect([pack].mod(withUniqueId: "") == nil)
    }
}

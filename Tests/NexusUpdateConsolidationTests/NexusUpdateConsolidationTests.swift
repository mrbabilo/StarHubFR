import Testing
import Foundation
@testable import StarHubTHCore

/// Le regroupement des mises à jour par pack décide de ce que tu vois dans
/// l'écran des mises à jour. Un pack de dix composants ne doit pas produire dix
/// lignes, et surtout : la ligne retenue ne doit pas en cacher une plus récente.
struct NexusUpdateConsolidationTests {
    /// `uniqueId` distinct de `nexusModId` par défaut : c'est la disposition
    /// réelle du parc, où 58 identifiants Nexus sont portés par plusieurs
    /// dossiers. Les faire coïncider dans les tests masquerait un
    /// regroupement qui se tromperait d'identité.
    private func update(_ id: String, name: String = "n",
                        latest: String, uploaded: Date? = nil) -> NexusUpdateChecker.ModUpdate {
        .init(uniqueId: "uid.\(id)", name: name, installedVersion: "1.0.0",
              latestVersion: latest,
              nexusModId: id, url: "https://x/\(id)", uploadedTime: uploaded)
    }
    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
    }

    @Test func aStandaloneModPassesThroughUnchanged() {
        let out = NexusUpdateConsolidation.consolidate([update("1", name: "Automate", latest: "2.0")],
                                                       parentPackName: [:])
        #expect(out.count == 1)
        #expect(out[0].name == "Automate")
    }

    @Test func componentsOfOnePackCollapseIntoASingleRowBearingThePackName() {
        let updates = [update("10", name: "RSV Core", latest: "1.0"),
                       update("11", name: "RSV Extras", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, parentPackName: ["10": "Ridgeside Village", "11": "Ridgeside Village"])
        #expect(out.count == 1)
        #expect(out[0].name == "Ridgeside Village")
    }

    @Test func theHighestVersionWinsWithinAPack() {
        // Le composant retenu porte la version la plus haute : retenir une
        // version inférieure ferait passer le pack pour à jour.
        let updates = [update("10", latest: "1.2.0"), update("11", latest: "1.10.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, parentPackName: ["10": "Pack", "11": "Pack"])
        #expect(out.count == 1)
        #expect(out[0].latestVersion == "1.10.0")
    }

    @Test func atEqualVersionsTheMostRecentUploadWins() {
        let updates = [update("10", latest: "2.0", uploaded: date(1)),
                       update("11", latest: "2.0", uploaded: date(9))]
        let out = NexusUpdateConsolidation.consolidate(
            updates, parentPackName: ["10": "Pack", "11": "Pack"])
        #expect(out[0].nexusModId == "11")
    }

    @Test func twoDifferentPacksStayTwoRows() {
        let updates = [update("10", latest: "1.0"), update("20", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, parentPackName: ["10": "Pack A", "20": "Pack B"])
        #expect(Set(out.map(\.name)) == ["Pack A", "Pack B"])
    }

    @Test func packsAndStandaloneModsCoexist() {
        let updates = [update("10", latest: "1.0"), update("11", latest: "1.0"),
                       update("99", name: "Automate", latest: "3.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, parentPackName: ["10": "Pack", "11": "Pack"])
        #expect(out.count == 2)
        #expect(Set(out.map(\.name)) == ["Pack", "Automate"])
    }

    @Test func rowsComeOutInAlphabeticalOrder() {
        let updates = [update("1", name: "Wallet Tools", latest: "1.0"),
                       update("2", name: "Automate", latest: "1.0"),
                       update("3", name: "Mapster", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(updates, parentPackName: [:])
        #expect(out.map(\.name) == ["Automate", "Mapster", "Wallet Tools"])
    }

    /// Le cas réel, et la raison du changement : la voie smapi.io construit
    /// chaque ligne avec `uploadedTime: nil`. Un tri par date les rendait
    /// toutes égales, et `sorted` n'est pas stable en Swift — l'ordre
    /// affiché n'était donc pas seulement dénué de sens, il pouvait changer
    /// d'une vérification à l'autre sans que rien ne bouge.
    @Test func rowsWithoutAnUploadDateAreStillOrdered() {
        let updates = [update("1", name: "Zoom", latest: "1.0"),
                       update("2", name: "Alpha", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(updates, parentPackName: [:])
        #expect(out.map(\.name) == ["Alpha", "Zoom"])
    }

    /// « automate » ne doit pas se ranger après « Zoom » : le tri ASCII met
    /// toutes les minuscules après toutes les majuscules, ce qu'aucun
    /// lecteur n'attend d'une liste de noms de mods.
    @Test func theOrderIgnoresCaseAndAccents() {
        let updates = [update("1", name: "Zoom", latest: "1.0"),
                       update("2", name: "automate", latest: "1.0"),
                       update("3", name: "Éclairage", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(updates, parentPackName: [:])
        #expect(out.map(\.name) == ["automate", "Éclairage", "Zoom"])
    }

    @Test func anEmptyInputYieldsNothing() {
        #expect(NexusUpdateConsolidation.consolidate([], parentPackName: ["1": "P"]).isEmpty)
    }

    @Test func theHighestVersionOfNothingIsNil() {
        // L'appel d'origine plantait sur une liste vide (`precondition`) ; il ne
        // pouvait pas l'être en pratique, mais rendre l'absence explicite retire
        // un point de crash au lieu de compter dessus.
        #expect(NexusUpdateConsolidation.highestVersion(among: []) == nil)
    }
}

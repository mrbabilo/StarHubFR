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
                                                       packNameByUniqueId: [:])
        #expect(out.count == 1)
        #expect(out[0].name == "Automate")
    }

    @Test func componentsOfOnePackCollapseIntoASingleRowBearingThePackName() {
        let updates = [update("10", name: "RSV Core", latest: "1.0"),
                       update("11", name: "RSV Extras", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, packNameByUniqueId: ["uid.10": "Ridgeside Village", "uid.11": "Ridgeside Village"])
        #expect(out.count == 1)
        #expect(out[0].name == "Ridgeside Village")
    }

    @Test func theHighestVersionWinsWithinAPack() {
        // Le composant retenu porte la version la plus haute : retenir une
        // version inférieure ferait passer le pack pour à jour.
        let updates = [update("10", latest: "1.2.0"), update("11", latest: "1.10.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, packNameByUniqueId: ["uid.10": "Pack", "uid.11": "Pack"])
        #expect(out.count == 1)
        #expect(out[0].latestVersion == "1.10.0")
    }

    @Test func atEqualVersionsTheMostRecentUploadWins() {
        let updates = [update("10", latest: "2.0", uploaded: date(1)),
                       update("11", latest: "2.0", uploaded: date(9))]
        let out = NexusUpdateConsolidation.consolidate(
            updates, packNameByUniqueId: ["uid.10": "Pack", "uid.11": "Pack"])
        #expect(out[0].nexusModId == "11")
    }

    @Test func twoDifferentPacksStayTwoRows() {
        let updates = [update("10", latest: "1.0"), update("20", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, packNameByUniqueId: ["uid.10": "Pack A", "uid.20": "Pack B"])
        #expect(Set(out.map(\.name)) == ["Pack A", "Pack B"])
    }

    @Test func packsAndStandaloneModsCoexist() {
        let updates = [update("10", latest: "1.0"), update("11", latest: "1.0"),
                       update("99", name: "Automate", latest: "3.0")]
        let out = NexusUpdateConsolidation.consolidate(
            updates, packNameByUniqueId: ["uid.10": "Pack", "uid.11": "Pack"])
        #expect(out.count == 2)
        #expect(Set(out.map(\.name)) == ["Pack", "Automate"])
    }

    @Test func rowsComeOutInAlphabeticalOrder() {
        let updates = [update("1", name: "Wallet Tools", latest: "1.0"),
                       update("2", name: "Automate", latest: "1.0"),
                       update("3", name: "Mapster", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(updates, packNameByUniqueId: [:])
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
        let out = NexusUpdateConsolidation.consolidate(updates, packNameByUniqueId: [:])
        #expect(out.map(\.name) == ["Alpha", "Zoom"])
    }

    /// « automate » ne doit pas se ranger après « Zoom » : le tri ASCII met
    /// toutes les minuscules après toutes les majuscules, ce qu'aucun
    /// lecteur n'attend d'une liste de noms de mods.
    @Test func theOrderIgnoresCaseAndAccents() {
        let updates = [update("1", name: "Zoom", latest: "1.0"),
                       update("2", name: "automate", latest: "1.0"),
                       update("3", name: "Éclairage", latest: "1.0")]
        let out = NexusUpdateConsolidation.consolidate(updates, packNameByUniqueId: [:])
        #expect(out.map(\.name) == ["automate", "Éclairage", "Zoom"])
    }

    @Test func anEmptyInputYieldsNothing() {
        #expect(NexusUpdateConsolidation.consolidate([], packNameByUniqueId: ["uid.1": "P"]).isEmpty)
    }

    @Test func theHighestVersionOfNothingIsNil() {
        // L'appel d'origine plantait sur une liste vide (`precondition`) ; il ne
        // pouvait pas l'être en pratique, mais rendre l'absence explicite retire
        // un point de crash au lieu de compter dessus.
        #expect(NexusUpdateConsolidation.highestVersion(among: []) == nil)
    }
}

/// L'identifiant Nexus n'est pas une identité — et cette table le supposait.
///
/// Mesuré sur le parc de l'auteur : **4 identifiants** sont déclarés à la fois
/// par l'enfant d'un pack et par un mod extérieur, et **2** par plusieurs packs
/// (`Nexus:8828` par trois). Indexer le regroupement dessus faisait disparaître
/// des lignes de l'écran des mises à jour.
struct NexusUpdateConsolidationIdentityTests {
    private func update(_ uid: String, nexus: String, name: String,
                        latest: String) -> NexusUpdateChecker.ModUpdate {
        .init(uniqueId: uid, name: name, installedVersion: "1.0.0", latestVersion: latest,
              nexusModId: nexus, url: "https://x/\(nexus)", uploadedTime: nil)
    }

    @Test func aStandaloneSharingItsNexusIdWithAPackIsNotSwallowed() {
        // Le cas réel : `Automate` déclare `Nexus:50165` — la page de
        // *Powered Automation*, une clé copiée par erreur — et
        // `luisMint.PoweredAutomation` est un composant du pack de ce nom.
        // Indexée sur l'identifiant, la table absorbait les deux : une seule
        // ligne, et la mise à jour d'`Automate` disparaissait.
        let out = NexusUpdateConsolidation.consolidate(
            [update("Pathoschild.Automate", nexus: "50165", name: "Automate", latest: "2.7.0"),
             update("luisMint.PoweredAutomation", nexus: "50165",
                    name: "Powered Automation", latest: "1.29.6")],
            packNameByUniqueId: ["luisMint.PoweredAutomation": "PoweredAutomation"])
        #expect(out.map(\.name) == ["Automate", "PoweredAutomation"])
    }

    @Test func twoPacksSharingANexusIdKeepTheirOwnNames() {
        // `Nexus:8828` est revendiqué par trois packs du parc. Indexée sur
        // l'identifiant, la table écrasait une entrée par l'autre : la mise à
        // jour d'un pack s'affichait sous le nom d'un autre.
        let out = NexusUpdateConsolidation.consolidate(
            [update("a.child", nexus: "8828", name: "A", latest: "2.0"),
             update("b.child", nexus: "8828", name: "B", latest: "3.0")],
            packNameByUniqueId: ["a.child": "Much Ado About Mushrooms",
                                 "b.child": "From Source to Sea"])
        #expect(out.map(\.name) == ["From Source to Sea", "Much Ado About Mushrooms"])
        #expect(out.first(where: { $0.name == "From Source to Sea" })?.latestVersion == "3.0")
    }

    @Test func aPackStillCollapsesWhenItsComponentsShareNothingButThePack() {
        // La contre-épreuve : le regroupement doit continuer de marcher pour
        // des composants aux identifiants Nexus **différents**, ce qui est le
        // cas ordinaire d'un pack.
        let out = NexusUpdateConsolidation.consolidate(
            [update("rsv.a", nexus: "10", name: "A", latest: "2.0"),
             update("rsv.b", nexus: "11", name: "B", latest: "3.0")],
            packNameByUniqueId: ["rsv.a": "Ridgeside Village", "rsv.b": "Ridgeside Village"])
        #expect(out.map(\.name) == ["Ridgeside Village"])
        #expect(out.first?.latestVersion == "3.0")
    }
}

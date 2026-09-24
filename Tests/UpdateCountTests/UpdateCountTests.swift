import Testing
import Foundation
@testable import StarHubTHCore

/// Le compte du badge « Mises à jour » : le relevé SMAPI du dernier
/// lancement, confronté au disque (X113). Mesuré sur le journal du
/// 2026-09-24 : `Wildroot Chronicles 1.3.5` suggéré, `Cropgenics` en 1.4.1
/// au disque — l'entrée ne doit plus compter.
@Suite struct UpdateCountTests {

    private func update(_ name: String, _ version: String) -> ModUpdateInfo {
        ModUpdateInfo(name: name, version: version,
                      url: "https://www.nexusmods.com/stardewvalley/mods/1")
    }

    // MARK: - La règle mesurée

    /// Le cas du parc : le disque est devant le relevé, l'entrée sort.
    @Test func leCasWildrootSortDuCompte() {
        let pending = UpdateCount.pending(
            outOfDate: [update("Wildroot Chronicles", "1.3.5")],
            nexusCount: 0) { name in
                name == "Wildroot Chronicles" ? "1.4.1" : nil
            }
        #expect(pending == 0)
    }

    /// Le cas voisin qui ne doit PAS sortir : le disque est derrière.
    @Test func leModVraimentEnRetardResteCompte() {
        let pending = UpdateCount.pending(
            outOfDate: [update("Kids for the School Tokens", "3.2.9")],
            nexusCount: 0) { _ in "3.2.3" }
        #expect(pending == 1)
    }

    /// La liste affichée (page Mises à jour) dérive de la même règle que le
    /// badge : l'entrée couverte par le disque ne se liste pas, l'autre si.
    @Test func laListeAfficheeFiltreCommeLeCompte() {
        let entries = UpdateCount.pendingEntries(
            outOfDate: [update("Wildroot Chronicles", "1.3.5"),
                        update("Kids for the School Tokens", "3.2.9")]) { name in
                name == "Wildroot Chronicles" ? "1.4.1" : "3.2.3"
            }
        #expect(entries.map(\.name) == ["Kids for the School Tokens"])
    }

    /// Compte et liste ne peuvent pas diverger : l'un dérive de l'autre.
    @Test func leCompteDeriveDeLaListe() {
        let updates = [update("Wildroot Chronicles", "1.3.5")]
        let disk: (String) -> String? = { $0 == "Wildroot Chronicles" ? "1.4.1" : nil }
        #expect(UpdateCount.pendingEntries(outOfDate: updates, diskVersion: disk).isEmpty)
        #expect(UpdateCount.pending(outOfDate: updates, nexusCount: 0, diskVersion: disk) == 0)
    }

    /// Parc vide ou nom non résolu : on ne juge rien, l'entrée reste comptée
    /// — gonfler le badge vaut mieux que l'écarter en silence.
    @Test func unNomNonResoluResteCompte() {
        let pending = UpdateCount.pending(
            outOfDate: [update("Mod Inconnu", "2.0")],
            nexusCount: 0) { _ in nil }
        #expect(pending == 1)
    }

    /// Le compte Nexus se additionne tel quel, sans jugement.
    @Test func leCompteNexusSadditionne() {
        let pending = UpdateCount.pending(
            outOfDate: [update("Wildroot Chronicles", "1.3.5")],
            nexusCount: 2) { $0 == "Wildroot Chronicles" ? "1.4.1" : nil }
        #expect(pending == 2)
    }

    // MARK: - La comparaison de versions

    @Test func versionsEgalesSontCouvertes() {
        #expect(UpdateCount.isAlreadyApplied(disk: "1.3.5", suggested: "1.3.5"))
    }

    /// Segment manquant = zéro : « 1.4 » couvre « 1.4.0 » et réciproquement.
    @Test func leSegmentManquantVautZero() {
        #expect(UpdateCount.isAlreadyApplied(disk: "1.4", suggested: "1.4.0"))
        #expect(UpdateCount.isAlreadyApplied(disk: "1.4.0", suggested: "1.4"))
    }

    /// Une étiquette non numérique coupe le préfixe sans l'invalider, et
    /// une version sans aucun chiffre ne se juge pas.
    @Test func etiquettesNonNumeriques() {
        #expect(UpdateCount.isAlreadyApplied(disk: "1.6.1-unofficial-2.dphill",
                                             suggested: "1.6.1"))
        #expect(!UpdateCount.isAlreadyApplied(disk: "1.6.0", suggested: "1.6.1-beta"))
        #expect(!UpdateCount.isAlreadyApplied(disk: "dev", suggested: "1.0"))
    }

    /// Un disque qui prolonge la ligne suggérée (« 3.2.3 » contre « 3 »)
    /// couvre déjà — le badge ne revient pas sur un « Je l'ai déjà ».
    @Test func leDisqueQuiProlongeLaLigneCouvre() {
        #expect(UpdateCount.isAlreadyApplied(disk: "3.2.3", suggested: "3"))
        #expect(!UpdateCount.isAlreadyApplied(disk: "2.9", suggested: "3"))
    }
}

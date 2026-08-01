import Testing
import Foundation
@testable import StarHubTHCore

/// Le registre décide de la date d'installation et de la version Nexus connue,
/// donc de la détection des mises à jour. Une date erronée signale une mise à
/// jour qui n'existe pas ; une version Nexus perdue en réintroduit une qui
/// avait été écartée.
struct InstalledModRegistryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)

    private func seen(_ folder: String, _ version: String,
                      nexus: String? = nil) -> InstalledModRegistry.Seen {
        .init(folder: folder, version: version, nexusVersion: nexus)
    }

    @Test func aModNeverSeenIsStampedWithTheCurrentTime() {
        let (reg, changed) = InstalledModRegistry.sync(
            registry: [:], seen: [seen("Automate", "1.0")], now: t0)
        #expect(changed)
        #expect(reg["Automate"]?.version == "1.0")
        #expect(reg["Automate"]?.installedAt == t0)
    }

    @Test func anUnchangedModDoesNotRewriteTheRegistry() {
        // Le cas le plus fréquent : un rafraîchissement sans rien de neuf.
        let current = ["Automate": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [seen("Automate", "1.0")], now: t1)
        #expect(!changed)
        #expect(reg["Automate"]?.installedAt == t0)
    }

    @Test func aVersionChangeRestampsTheInstallDate() {
        let current = ["Automate": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [seen("Automate", "2.0")], now: t1)
        #expect(changed)
        #expect(reg["Automate"]?.installedAt == t1)
    }

    @Test func aVersionChangeCarriesOverTheKnownNexusVersion() {
        // Sans ce report, une réinstallation ferait réapparaître une mise à
        // jour déjà écartée.
        let current = ["A": InstalledModRecord(version: "1.0", installedAt: t0, nexusVersion: "3.0")]
        let (reg, _) = InstalledModRegistry.sync(
            registry: current, seen: [seen("A", "2.0")], now: t1)
        #expect(reg["A"]?.nexusVersion == "3.0")
    }

    @Test func aFreshlyLearnedNexusVersionWinsOverTheCarriedOne() {
        let current = ["A": InstalledModRecord(version: "1.0", installedAt: t0, nexusVersion: "3.0")]
        let (reg, _) = InstalledModRegistry.sync(
            registry: current, seen: [seen("A", "2.0", nexus: "4.0")], now: t1)
        #expect(reg["A"]?.nexusVersion == "4.0")
    }

    @Test func learningTheNexusVersionDoesNotTouchTheInstallDate() {
        // Première vérification Nexus après une pose manuelle : on enregistre
        // ce qu'on apprend, sans faire croire à une réinstallation.
        let current = ["A": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [seen("A", "1.0", nexus: "3.0")], now: t1)
        #expect(changed)
        #expect(reg["A"]?.nexusVersion == "3.0")
        #expect(reg["A"]?.installedAt == t0)
        #expect(reg["A"]?.version == "1.0")
    }

    @Test func anEmptyOrBlankNexusVersionCountsAsUnknown() {
        let (reg, _) = InstalledModRegistry.sync(
            registry: [:], seen: [seen("A", "1.0", nexus: "   ")], now: t0)
        #expect(reg["A"]?.nexusVersion == nil)
    }

    @Test func aFolderGoneFromDiskLeavesTheRegistry() {
        let current = ["Parti": InstalledModRecord(version: "1.0", installedAt: t0),
                       "Resté": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [seen("Resté", "1.0")], now: t1)
        #expect(changed)
        #expect(Array(reg.keys) == ["Resté"])
    }

    @Test func pruningAloneCountsAsAChange() {
        // Rien de neuf côté mods, mais un dossier a disparu : il faut écrire.
        let current = ["Parti": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(registry: current, seen: [], now: t1)
        #expect(changed)
        #expect(reg.isEmpty)
    }

    @Test func anEmptyScanOnAnEmptyRegistryChangesNothing() {
        let (reg, changed) = InstalledModRegistry.sync(registry: [:], seen: [], now: t0)
        #expect(!changed)
        #expect(reg.isEmpty)
    }
}

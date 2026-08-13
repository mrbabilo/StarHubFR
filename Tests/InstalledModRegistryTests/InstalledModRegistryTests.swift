import Testing
import Foundation
@testable import StarHubTHCore

/// Le registre décide de la date d'installation à partir de ce que le scan a
/// vu sur disque. Une date erronée signale une mise à jour qui n'existe pas.
struct InstalledModRegistryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)

    private func seen(_ folder: String, _ version: String) -> InstalledModRegistry.Seen {
        .init(folder: folder, version: version)
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

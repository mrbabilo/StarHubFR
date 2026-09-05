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

    // MARK: - Grâce sur la date d'installation

    // Le retrait de `nexusVersion` a changé ce que le registre enregistre :
    // avant, la version Nexus quand elle était plus haute ; maintenant, celle
    // du manifest. Au premier scan, ~52 dossiers du parc réel voient donc leur
    // version « changer » sans que le disque ait bougé — et seraient
    // ré-estampillés à maintenant, écrasant sans retour la seule trace de leur
    // date d'installation.

    @Test func aFolderUnderGraceKeepsItsInstallDateWhenTheVersionChanges() {
        let current = ["A": InstalledModRecord(version: "3.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [seen("A", "1.0")], now: t1,
            installDateGrace: ["A"])
        #expect(changed, "la version enregistrée change bien")
        #expect(reg["A"]?.version == "1.0")
        #expect(reg["A"]?.installedAt == t0, "la date d'origine survit")
    }

    @Test func aFolderOutsideGraceIsRestampedAsBefore() {
        let current = ["B": InstalledModRecord(version: "3.0", installedAt: t0)]
        let (reg, _) = InstalledModRegistry.sync(
            registry: current, seen: [seen("B", "1.0")], now: t1,
            installDateGrace: ["A"])
        #expect(reg["B"]?.installedAt == t1)
    }

    @Test func graceDoesNotApplyToAFolderTheRegistryHasNeverSeen() {
        // Un dossier neuf s'horodate à maintenant, grâce ou pas : il n'y a
        // aucune date d'origine à préserver.
        let (reg, _) = InstalledModRegistry.sync(
            registry: [:], seen: [seen("A", "1.0")], now: t1,
            installDateGrace: ["A"])
        #expect(reg["A"]?.installedAt == t1)
    }

    @Test func graceLeavesAnUnchangedVersionAlone() {
        let current = ["A": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [seen("A", "1.0")], now: t1,
            installDateGrace: ["A"])
        #expect(!changed)
        #expect(reg["A"]?.installedAt == t0)
    }

    @Test func aSecondVersionChangeRestampsEvenAFormerlyGracedFolder() {
        // La grâce ne vaut que pour la passe qui suit la migration ; l'appelant
        // vide le lot ensuite. Une vraie mise à jour, plus tard, doit bien
        // ré-estampiller — sans quoi la date resterait fausse à jamais.
        let afterGrace = ["A": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, _) = InstalledModRegistry.sync(
            registry: afterGrace, seen: [seen("A", "2.0")], now: t1,
            installDateGrace: [])
        #expect(reg["A"]?.installedAt == t1)
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

    // MARK: - « Rien vu » n'est pas « rien installé »

    @Test func aScanThatCouldNotReadTheFolderPrunesNothing() {
        // X71 : `Mods/` illisible (dossier de jeu déplacé, volume débranché,
        // droits refusés) rend un lot vide. Purger sur cette base efface tout
        // le registre — 1 097 entrées sur le parc de référence — et sa copie de
        // secours avec, puisque les deux clés reçoivent le même blob.
        let current = ["Automate": InstalledModRecord(version: "1.0", installedAt: t0),
                       "SVE": InstalledModRecord(version: "2.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [], now: t1, pruneMissing: false)
        #expect(!changed)
        #expect(reg.count == 2)
        #expect(reg["Automate"]?.installedAt == t0)
    }

    @Test func aReadableButEmptyFolderStillPrunes() {
        // Le cas voisin qui doit continuer de purger : le dossier a bien été
        // lu, il ne contient plus rien. C'est une désinstallation réelle.
        let current = ["Parti": InstalledModRecord(version: "1.0", installedAt: t0)]
        let (reg, changed) = InstalledModRegistry.sync(
            registry: current, seen: [], now: t1, pruneMissing: true)
        #expect(changed)
        #expect(reg.isEmpty)
    }

    @Test func anUnreadableScanStillRecordsWhatItDidSee() {
        // Un lot partiel reste utile : ce qu'on a vu s'enregistre, seule la
        // purge est suspendue.
        let (reg, changed) = InstalledModRegistry.sync(
            registry: [:], seen: [seen("Automate", "1.0")], now: t0, pruneMissing: false)
        #expect(changed)
        #expect(reg["Automate"]?.installedAt == t0)
    }
}

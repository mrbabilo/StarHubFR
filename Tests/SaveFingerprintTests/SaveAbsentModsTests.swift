import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T9 — « utilisés avec cette partie, plus installés » : seule la clé
/// SMAPI porte l'UniqueID exact. Clés copiées de Zofia (2026-09-23).
@Suite struct SaveAbsentModsTests {
    private func mod(_ id: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: id, version: "1",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    @Test("Un uid SMAPI absent du parc sort, avec son nombre de clés")
    func absentUidIsListed() {
        let s = SaveFingerprintScan(modDataKeys: [
            "smapi/mod-data/aloofllama.giftdiscovery/state": 2,
            "smapi/mod-data/spacechase0.spacecore/skills": 1,
        ])
        #expect(SaveAbsentMods.entries(scan: s, mods: [mod("spacechase0.SpaceCore")])
            == [AbsentModFootprint(uid: "aloofllama.giftdiscovery", keys: 2)])
    }

    @Test("Un mod en pause n'est pas « plus installé » ; la casse est ignorée")
    func pausedModIsNotAbsent() {
        let s = SaveFingerprintScan(modDataKeys: [
            "smapi/mod-data/bindicle.dayswork/data": 1,
        ])
        #expect(SaveAbsentMods.entries(
            scan: s, mods: [mod("Bindicle.Dayswork", enabled: false)]).isEmpty)
    }

    @Test("Un mod absorbé par un mod installé (legacy-migrated) n'est pas listé")
    func migratedModIsNotListed() {
        let s = SaveFingerprintScan(modDataKeys: [
            "smapi/mod-data/thalethegreat.walletautopetter/walletautopetter.state": 1,
            "smapi/mod-data/thalethegreat.wallettools/"
                + "legacy-migrated-thalethegreat.walletautopetter-walletautopetter.state": 1,
        ])
        #expect(SaveAbsentMods.entries(
            scan: s, mods: [mod("ThaleTheGreat.WalletTools")]).isEmpty)
    }

    @Test("Une tête <x>/ inconnue n'est pas une preuve d'absence")
    func unknownSlashHeadIsIgnored() {
        let s = SaveFingerprintScan(modDataKeys: ["foxisadev.bqr/done": 33])
        #expect(SaveAbsentMods.entries(scan: s, mods: []).isEmpty)
    }

    @Test("Les plus chargés d'abord, puis par uid")
    func sortedByKeysThenUid() {
        let s = SaveFingerprintScan(modDataKeys: [
            "smapi/mod-data/b.b/x": 1,
            "smapi/mod-data/a.a/x": 1,
            "smapi/mod-data/c.c/x": 3,
        ])
        #expect(SaveAbsentMods.entries(scan: s, mods: []).map(\.uid)
            == ["c.c", "a.a", "b.b"])
    }
}

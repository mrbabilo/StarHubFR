import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T10 — après un nettoyage, la section ne doit pas remontrer l'ancienne
/// liste (et son bouton) pendant les ~10 s du rescan : une save réécrite
/// repasse en lecture. Un changement du seul parc, lui, garde l'affichage.
@Suite @MainActor struct SaveAbsentModsStoreTests {
    private func save(_ url: URL, modified: Date) -> SaveGameInfo {
        SaveGameInfo(
            folderName: "Probe_\(url.lastPathComponent)", fileURL: url, lastModified: modified,
            playerName: "P", farmName: "F", favoriteThing: "", money: 0,
            spouse: "", maxHealth: 100, maxStamina: 270, goldenWalnuts: 0,
            qiGems: 0, clubCoins: 0, totalMoneyEarned: 0,
            year: 1, season: 0, day: 1, whichFarm: 0)
    }

    private func loaded(_ store: SaveAbsentModsStore) async -> Bool {
        for _ in 0..<500 {
            if case .loaded = store.state { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test("Une save réécrite repasse en lecture ; le parc seul garde la liste")
    func rewrittenSaveRescansVisibly() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)")
        try Data("<modData><item><key><string>smapi/mod-data/gone.g/x</string></key><value><string>1</string></value></item></modData>".utf8)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let avant = Date(timeIntervalSince1970: 1_000)
        let store = SaveAbsentModsStore()

        store.refresh(save: save(url, modified: avant), mods: [])
        let premier = await loaded(store)
        #expect(premier)

        // Le parc change, pas la save : l'affichage reste.
        store.refresh(save: save(url, modified: avant), mods: [])
        let resté: Bool
        if case .loaded = store.state { resté = true } else { resté = false }
        #expect(resté)

        // La save est réécrite (nouvelle date) : lecture immédiate.
        store.refresh(save: save(url, modified: avant), mods: [], modified: Date())
        #expect(store.state == .scanning)
    }
}

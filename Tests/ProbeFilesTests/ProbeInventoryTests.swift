import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeInventoryTests {
    private func decoded() throws -> (launches: [ProbeInventoryLaunch],
                                      changes: [ProbeInventoryChange], unreadable: Int) {
        ProbeInventory.decode(try Fixture.data("inventory.jsonl"))
    }

    /// Deux lancements (0.4.12 puis 0.4.13), la coupure de la seconde. La
    /// ligne coupée net par `pick` : comptée, jamais levée.
    @Test func twoLaunchesAndOneChange() throws {
        let result = try decoded()
        #expect(result.launches.count == 2)
        #expect(result.launches.map(\.probe) == ["0.4.12", "0.4.13"])
        #expect(result.changes.count == 1)
        #expect(result.changes[0].session.hasPrefix("2026-09-28T19:21"))
        #expect(result.unreadable == 1)
    }

    @Test func launchCarriesItsMods() throws {
        let launch = try decoded().launches[1]
        #expect(launch.mods.count == 289)
        #expect(launch.mods.filter { $0.configSha != nil }.count == 174)
        let gmcm = launch.byModId["spacechase0.GenericModConfigMenu"]
        #expect(gmcm?.configSha?.hasPrefix("3fa643ce") == true)
    }

    /// `ChangedAt` se lit ; `Configs` porte `sha | null`.
    @Test func changeCarriesChangedAtAndConfigs() throws {
        let change = try decoded().changes[0]
        #expect(change.changedAt != nil)
        let gmcm = try #require(change.configs["spacechase0.GenericModConfigMenu"])
        #expect(gmcm?.hasPrefix("bbe0048a") == true)
    }

    /// Les clés de `Configs` sont des identifiants de mods : leur casse
    /// arrive intacte, même en majuscule initiale (SVE). Une valeur `null`
    /// (config supprimé) reste une clé présente.
    @Test func configKeysKeepTheirCaseAndNullStaysAKey() throws {
        let data = Data(#"{"Session":"s","At":"2026-01-01T00:00:00.0000000+00:00","Kind":"configChanged","Configs":{"FlashShifter.StardewValleyExpandedCP":"abc","Gone.Mod":null}}"#.utf8)
        let result = ProbeInventory.decode(data)
        #expect(result.changes.count == 1)
        #expect(result.changes[0].configs["FlashShifter.StardewValleyExpandedCP"] == .some("abc"))
        #expect(result.changes[0].configs["Gone.Mod"] == .some(nil))
    }

    /// Ligne absente du champ `Kind` (fichier d'une sonde future) : comptée.
    @Test func alienLineCountedNotThrown() throws {
        let data = Data("{\"Session\":\"2026-01-01T00:00:00.0000000+00:00\"}\n".utf8)
        let result = ProbeInventory.decode(data)
        #expect(result.launches.isEmpty && result.changes.isEmpty && result.unreadable == 1)
    }
}

import Foundation
import Testing
@testable import StarHubTHCore

/// Mimique le comportement du VM : retourne la traduction si présente, sinon la clé brute.
/// Permet de tester `String(format:)` avec une chaîne contenant `%@`.
private final class KeyReturningResolver: L10nResolver {
    private let translations: [String: String]
    init(translations: [String: String] = [:]) {
        self.translations = translations
    }
    func localized(_ key: String) -> String {
        translations[key] ?? key
    }
}

private func makeSave(whichFarm: Int, modFarmName: String? = nil) -> SaveGameInfo {
    SaveGameInfo(
        folderName: "TestSave_\(whichFarm)",
        fileURL: URL(fileURLWithPath: "/tmp/TestSave_\(whichFarm)"),
        lastModified: Date(timeIntervalSince1970: 0),
        playerName: "Test",
        farmName: "TestFarm",
        favoriteThing: "Testing",
        money: 0,
        spouse: "",
        maxHealth: 100,
        maxStamina: 270,
        goldenWalnuts: 0,
        qiGems: 0,
        clubCoins: 0,
        totalMoneyEarned: 0,
        year: 1,
        season: 0,
        day: 1,
        whichFarm: whichFarm,
        modFarmName: modFarmName
    )
}

@Suite struct SaveFarmNameResolverTests {
    @Test func resolveVanillaFarm() {
        let resolver = KeyReturningResolver()
        let info = makeSave(whichFarm: 0)
        #expect(SaveFarmNameResolver.resolve(info, resolver: resolver) == "saves_farm_type_standard")
    }

    @Test func resolveModFarmWithName() {
        let resolver = KeyReturningResolver()
        let info = makeSave(whichFarm: 99, modFarmName: "Ridgeside")
        #expect(SaveFarmNameResolver.resolve(info, resolver: resolver) == "Ridgeside")
    }

    @Test func resolveModFarmWithoutName() {
        let resolver = KeyReturningResolver()
        let info = makeSave(whichFarm: 99, modFarmName: nil)
        #expect(SaveFarmNameResolver.resolve(info, resolver: resolver) == "saves_farm_type_mod")
    }

    @Test func heroHelpFormat() {
        let resolver = KeyReturningResolver(translations: [
            L10n.Saves.heroFarmHelpFormat: "Farm type: %@"
        ])
        let info = makeSave(whichFarm: 0)
        #expect(SaveFarmNameResolver.heroHelp(for: info, resolver: resolver) == "Farm type: saves_farm_type_standard")
    }
}
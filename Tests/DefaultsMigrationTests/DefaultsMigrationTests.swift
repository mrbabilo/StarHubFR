import Testing
import Foundation
@testable import StarHubTHCore

struct DefaultsMigrationTests {
    /// Deux suites jetables, jamais `UserDefaults.standard` : il porte les
    /// données réelles du parc.
    private func suites() -> (from: UserDefaults, to: UserDefaults, names: (String, String)) {
        let a = "test.migration.from.\(UUID().uuidString)"
        let b = "test.migration.to.\(UUID().uuidString)"
        return (UserDefaults(suiteName: a)!, UserDefaults(suiteName: b)!, (a, b))
    }

    private func cleanUp(_ names: (String, String)) {
        UserDefaults.standard.removePersistentDomain(forName: names.0)
        UserDefaults.standard.removePersistentDomain(forName: names.1)
    }

    @Test func namedKeysAreCopied() {
        let s = suites(); defer { cleanUp(s.names) }
        s.from.set("/Applications/Stardew Valley.app", forKey: "gameDir")
        s.from.set(Data([1, 2, 3]), forKey: "modProfiles")
        #expect(DefaultsMigration.copy(from: s.from, to: s.to,
                                       keys: ["gameDir", "modProfiles"]) == 2)
        #expect(s.to.string(forKey: "gameDir") == "/Applications/Stardew Valley.app")
        #expect(s.to.data(forKey: "modProfiles") == Data([1, 2, 3]))
    }

    /// **Ne jamais écraser.** Si la nouvelle installation a déjà une valeur,
    /// elle est plus récente que celle de l'ancienne : la recopie doit la
    /// laisser.
    @Test func anExistingValueIsNeverOverwritten() {
        let s = suites(); defer { cleanUp(s.names) }
        s.from.set("ancien", forKey: "gameDir")
        s.to.set("récent", forKey: "gameDir")
        #expect(DefaultsMigration.copy(from: s.from, to: s.to, keys: ["gameDir"]) == 0)
        #expect(s.to.string(forKey: "gameDir") == "récent")
    }

    /// Une clé absente de la source ne compte pas comme recopiée.
    @Test func missingKeysAreNotCounted() {
        let s = suites(); defer { cleanUp(s.names) }
        #expect(DefaultsMigration.copy(from: s.from, to: s.to, keys: ["gameDir"]) == 0)
    }

    /// La liste des clés possédées est maintenue à la main : un doublon ou une
    /// clé vide n'y a pas sa place — et `AppleLanguages` non plus, l'app la
    /// re-dérive de `currentLanguage` après la recopie.
    @Test func ownedKeysAreClean() {
        #expect(Set(DefaultsMigration.ownedKeys).count == DefaultsMigration.ownedKeys.count)
        #expect(DefaultsMigration.ownedKeys.allSatisfy { !$0.isEmpty })
        #expect(!DefaultsMigration.ownedKeys.contains("AppleLanguages"))
    }
}

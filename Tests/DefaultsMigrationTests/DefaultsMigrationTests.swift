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

    // MARK: - La reprise, une fois et une seule (revue F5, constat 1)

    /// **Le constat qui a motivé le correctif.** La recopie tournait à chaque
    /// lancement : toute clé que l'app efface volontairement — `activeProfileId`
    /// quand on désélectionne un profil, les caches Nexus qu'on purge, le
    /// registre purgé pour corruption — revenait au lancement suivant, reprise
    /// de l'ancien domaine.
    @Test func aDeletedKeyIsNeverResurrected() {
        let s = suites(); defer { cleanUp(s.names) }
        s.from.set("ancien-profil", forKey: "activeProfileId")

        #expect(DefaultsMigration.importLegacyIfNeeded(from: s.from, to: s.to) == 1)
        #expect(s.to.string(forKey: "activeProfileId") == "ancien-profil")

        // L'utilisateur désélectionne son profil : l'app efface la clé.
        s.to.removeObject(forKey: "activeProfileId")

        // Second lancement : rien ne doit revenir.
        #expect(DefaultsMigration.importLegacyIfNeeded(from: s.from, to: s.to) == 0)
        #expect(s.to.string(forKey: "activeProfileId") == nil)
    }

    /// Le marqueur est posé **inconditionnellement**, y compris quand il n'y a
    /// rien à reprendre : sans cela, une installation neuve rejouerait la
    /// reprise à chaque lancement et resterait exposée au même défaut.
    @Test func theMarkerIsSetEvenWithNothingToImport() {
        let s = suites(); defer { cleanUp(s.names) }
        #expect(DefaultsMigration.importLegacyIfNeeded(from: s.from, to: s.to) == 0)
        #expect(s.to.bool(forKey: DefaultsMigration.completionMarker))
    }

    /// Une installation sans ancien domaine du tout (source `nil`) pose le
    /// marqueur elle aussi.
    @Test func aFreshInstallWithoutLegacyIsMarkedDone() {
        let s = suites(); defer { cleanUp(s.names) }
        #expect(DefaultsMigration.importLegacyIfNeeded(from: nil, to: s.to) == 0)
        #expect(s.to.bool(forKey: DefaultsMigration.completionMarker))
    }

    /// Le marqueur décrit **l'installation courante**, pas une donnée à
    /// hériter : le recopier ferait croire à une reprise déjà faite.
    @Test func theMarkerIsNotItselfImported() {
        #expect(!DefaultsMigration.ownedKeys.contains(DefaultsMigration.completionMarker))
    }

    /// La clé d'API Nexus vit au **Trousseau** depuis F5-T6 ; plus aucun
    /// lecteur `UserDefaults` ne l'interroge. La recopier écrirait un
    /// identifiant dans un plist neuf pour personne.
    @Test func theNexusApiKeyIsNotCarriedIntoPreferences() {
        #expect(!DefaultsMigration.ownedKeys.contains("nexusApiKey"))
    }
}

import Foundation
import Testing
@testable import StarHubTHCore

/// Le store du domaine Localisation (REFACTORING §6) : langue d'interface,
/// persistance, résolution des clés L10n.
///
/// Les préférences passent par une suite jetable (CLAUDE.md : aucun test
/// n'écrit dans le vrai domaine) et les `.lproj` sont de vrais bundles
/// construits dans un dossier temporaire — c'est le seul moyen de tester la
/// chaîne complète `Bundle(url:)` → `localizedString`, le seam
/// `resourceURL` existant pour ça.
@Suite struct LocalizationStoreTests {

    private let fm = FileManager.default

    /// Suite UserDefaults jetable, unique par essai.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LocalizationStoreTests-\(UUID().uuidString)")!
    }

    /// Une racine de ressources avec `fr.lproj` et `en.lproj` réels.
    /// Retourne le dossier à passer en `resourceURL`.
    private func makeResourceURL(fr: String = "Bonjour",
                                 en: String = "Hello") throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (code, value) in [("fr", fr), ("en", en)] {
            let lproj = root.appendingPathComponent("\(code).lproj")
            try fm.createDirectory(at: lproj, withIntermediateDirectories: true)
            let content = "\"greeting\" = \"\(value)\";\n"
            try content.write(to: lproj.appendingPathComponent("Localizable.strings"),
                              atomically: true, encoding: .utf8)
        }
        return root
    }

    // MARK: - Langue initiale

    /// Choix du fork : premier lancement sans valeur sauvegardée → français,
    /// quelle que soit la locale du système.
    @Test func firstLaunchDefaultsToFrench() {
        let store = LocalizationStore(defaults: makeDefaults(), resourceURL: nil)
        #expect(store.currentLanguage == "fr")
    }

    /// Un choix existant est toujours respecté — y compris l'anglais choisi
    /// explicitement par l'utilisateur.
    @Test func savedChoiceIsRespected() {
        let defaults = makeDefaults()
        defaults.set("en", forKey: UDKey.currentLanguage)
        let store = LocalizationStore(defaults: defaults, resourceURL: nil)
        #expect(store.currentLanguage == "en")
    }

    /// Une valeur non supportée relue des préférences tombe sur le repli.
    @Test func unsupportedSavedValueFallsBackToFrench() {
        let defaults = makeDefaults()
        defaults.set("de", forKey: UDKey.currentLanguage)
        let store = LocalizationStore(defaults: defaults, resourceURL: nil)
        #expect(store.currentLanguage == "fr")
    }

    /// Le chargement initial n'écrit rien : une absence reste une absence.
    /// `ModConfigBackup`/`ModInstallBackup` relisent la clé en direct avec
    /// leur propre repli — un écrit au lancement changerait leur comportement.
    @Test func initDoesNotWriteDefaults() {
        let defaults = makeDefaults()
        _ = LocalizationStore(defaults: defaults, resourceURL: nil)
        #expect(defaults.object(forKey: UDKey.currentLanguage) == nil)
    }

    // MARK: - Changement de langue

    @Test func setLanguagePersists() {
        let defaults = makeDefaults()
        let store = LocalizationStore(defaults: defaults, resourceURL: nil)
        store.setLanguage("en")
        #expect(store.currentLanguage == "en")
        #expect(defaults.string(forKey: UDKey.currentLanguage) == "en")
    }

    /// Chaque écriture resynchronise `AppleLanguages` — les vues système
    /// (formateurs, panneau d'ouverture) suivent la langue de l'app.
    @Test func setLanguageResyncsAppleLanguages() {
        let defaults = makeDefaults()
        let store = LocalizationStore(defaults: defaults, resourceURL: nil)
        store.setLanguage("en")
        #expect(defaults.stringArray(forKey: UDKey.appleLanguagesOverride) == ["en"])
    }

    /// La cascade documentée au `didSet` : une écriture non supportée est
    /// réécrite puis persistée sous forme normalisée — l'état en mémoire et
    /// l'état sur disque ne peuvent pas diverger.
    @Test func unsupportedWriteFallsBackToFrenchEverywhere() {
        let defaults = makeDefaults()
        let store = LocalizationStore(defaults: defaults, resourceURL: nil)
        store.setLanguage("de")
        #expect(store.currentLanguage == "fr")
        #expect(defaults.string(forKey: UDKey.currentLanguage) == "fr")
        #expect(defaults.stringArray(forKey: UDKey.appleLanguagesOverride) == ["fr"])
    }

    // MARK: - Résolution des clés

    /// Sans ressource, pas de crash : la clé elle-même revient, pour que
    /// une traduction manquante reste visible à l'écran.
    @Test func missingResourceReturnsKeyItself() {
        let store = LocalizationStore(defaults: makeDefaults(), resourceURL: nil)
        #expect(store.L("some.missing.key") == "some.missing.key")
        #expect(store.localizedString(for: "some.missing.key") == "some.missing.key")
    }

    /// Une racine présente mais sans le `.lproj` demandé : même repli.
    @Test func missingLprojReturnsKeyItself() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LocalizationStore(defaults: makeDefaults(), resourceURL: root)
        #expect(store.L("some.missing.key") == "some.missing.key")
    }

    /// La chaîne complète : un vrai bundle, un vrai `.strings`.
    @Test func resolvesFromRealBundle() throws {
        let store = LocalizationStore(defaults: makeDefaults(),
                                      resourceURL: try makeResourceURL())
        #expect(store.L("greeting") == "Bonjour")
    }

    /// Le cœur du domaine vu de l'écran : basculer la langue bascule les
    /// libellés, dans les deux sens.
    @Test func switchingLanguageSwitchesValues() throws {
        let store = LocalizationStore(defaults: makeDefaults(),
                                      resourceURL: try makeResourceURL())
        store.setLanguage("en")
        #expect(store.L("greeting") == "Hello")
        store.setLanguage("fr")
        #expect(store.L("greeting") == "Bonjour")
    }

    /// Le cache ne fige pas la première langue : après bascule, la valeur
    /// suit (le cache est indexé par langue, pas global).
    @Test func cachedBundleFollowsLanguageSwitch() throws {
        let store = LocalizationStore(defaults: makeDefaults(),
                                      resourceURL: try makeResourceURL())
        _ = store.L("greeting")     // peuple le cache avec le bundle fr
        store.setLanguage("en")
        _ = store.L("greeting")     // peuple le cache avec le bundle en
        store.setLanguage("fr")
        #expect(store.L("greeting") == "Bonjour")
    }

    // MARK: - Protocole du dépôt

    /// `SaveFarmNameResolver` consomme le store via `L10nResolver` — la
    /// conformité délègue exactement à `L(_:)`.
    @Test func l10nResolverConformance() throws {
        let store = LocalizationStore(defaults: makeDefaults(),
                                      resourceURL: try makeResourceURL())
        let resolver: L10nResolver = store
        #expect(resolver.localized("greeting") == store.L("greeting"))
        #expect(resolver.localized("greeting") == "Bonjour")
    }
}

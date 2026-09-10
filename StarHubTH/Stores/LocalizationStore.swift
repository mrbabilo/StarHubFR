import Foundation
import Combine

/// Le domaine Localisation (REFACTORING §6) : la langue d'interface et la
/// résolution des clés L10n. Extrait du ViewModel le 2026-09-10 — les trois
/// fonctions du domaine (`L(_:)`, `localizedString(for:)`,
/// `cachedBundle(for:)`) et l'état `currentLanguage` n'avaient aucune
/// logique hors d'eux.
///
/// « Ce qui n'est pas à moi arrive en paramètre » (§3) : les préférences
/// (`defaults`, comme `GameEnvironmentStore`) et la racine des ressources
/// (`resourceURL`) arrivent par l'initialiseur. Le second est le seam de
/// test de `Bundle.main`, dont l'app n'existe pas sous `swift test`.
///
/// Threading — contrat hérité du VM : `L(_:)` est appelé depuis le fil
/// principal **et** depuis les files de fond (`fetchSteamUser` évalue son
/// repli « Farmer » hors main, le VM l'appelle aussi depuis son init et
/// ses passes de traduction). Le cache de bundles est donc verrouillé ; la
/// lecture de `currentLanguage` hors main, elle, existait déjà telle
/// quelle dans le VM — comportement conservé, pas un contrat nouveau.
final class LocalizationStore: ObservableObject {

    /// Langue d'interface, « en » ou « fr » — les seules depuis le retrait
    /// du thaï. Persistée dans `UDKey.currentLanguage` (lue aussi en direct
    /// par `ModConfigBackup`/`ModInstallBackup` pour la locale de leurs
    /// formateurs de dates) ; chaque écriture resynchronise
    /// `UDKey.appleLanguagesOverride` pour les vues système.
    @Published private(set) var currentLanguage: String {
        didSet {
            // Normalize first: a non-supported value is rewritten in-place,
            // which re-enters `didSet` once with a supported value — at which
            // point we fall through to the persistence write. This avoids the
            // previous "write then reassign" cascade where the rejection path
            // left the in-memory and on-disk values out of sync.
            let normalized = Self.normalized(currentLanguage)
            if normalized != currentLanguage {
                currentLanguage = normalized
                return
            }
            defaults.set(normalized, forKey: UDKey.currentLanguage)
            defaults.set([normalized], forKey: UDKey.appleLanguagesOverride)
        }
    }

    private let defaults: UserDefaults
    /// Racine des ressources où vivent `en.lproj`/`fr.lproj`. C'est
    /// `Bundle.main.resourceURL` en production ; injectable en test.
    private let resourceURL: URL?

    /// This fork (StarHubFR) launches in **French by default**, regardless of
    /// the system locale — English is only used when the user explicitly picks
    /// it (via the sidebar flag toggle). Only affects a first launch with no
    /// saved `currentLanguage`; an existing choice is always respected.
    private static var defaultLanguage: String { "fr" }
    private static let supportedLanguages = Set(["en", "fr"])

    private static func normalized(_ language: String?) -> String {
        guard let language, supportedLanguages.contains(language) else { return defaultLanguage }
        return language
    }

    init(defaults: UserDefaults = .standard,
         resourceURL: URL? = Bundle.main.resourceURL) {
        self.defaults = defaults
        self.resourceURL = resourceURL
        // `didSet` ne voit pas la valeur d'initialisation : aucun écrit aux
        // préférences au lancement — un choix sauvegardé est lu tel quel,
        // une absence n'écrit rien, comme dans le VM d'origine.
        self.currentLanguage = Self.normalized(defaults.string(forKey: UDKey.currentLanguage))
    }

    // MARK: - Changement de langue

    /// Porte d'entrée unique pour changer de langue. La normalisation vit
    /// dans le `didSet` : une valeur non supportée y est réécrite puis
    /// persistée sous sa forme normalisée (cascade documentée ci-dessus) —
    /// l'état en mémoire et l'état sur disque ne peuvent pas diverger.
    func setLanguage(_ language: String) {
        currentLanguage = language
    }

    // MARK: - Résolution des clés

    func localizedString(for key: String) -> String {
        if let bundle = cachedBundle(for: currentLanguage) {
            let result = bundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
            if result != "__MISSING__" { return result }
        }
        // Last resort: return key so missing translations are visible
        return key
    }

    /// Typed-key shorthand. Prefer this over localizedString(for:) with raw strings.
    /// Example: l10n.L(L10n.Mods.enabled)
    func L(_ key: String) -> String {
        localizedString(for: key)
    }

    // MARK: - Cache de bundles

    /// Cache **d'instance** — écart consigné au §6 : le VM le portait en
    /// `static`. Même comportement pour l'app, qui ne crée qu'un store ;
    /// en test, chaque essai a son cache au lieu d'un cache de type partagé
    /// entre essais (CLAUDE.md : un cache global impose des tests
    /// `.serialized`). Le verrou reste : `L(_:)` passe sur plusieurs fils.
    private var bundleCache: [String: Bundle] = [:]
    private let bundleCacheLock = NSLock()

    private func cachedBundle(for language: String) -> Bundle? {
        bundleCacheLock.lock()
        let cached = bundleCache[language]
        bundleCacheLock.unlock()
        if let cached = cached { return cached }

        guard let resourceURL else { return nil }
        let lprojURL = resourceURL.appendingPathComponent("\(language).lproj")
        guard let bundle = Bundle(url: lprojURL) else { return nil }

        bundleCacheLock.lock()
        bundleCache[language] = bundle
        bundleCacheLock.unlock()
        return bundle
    }
}

/// Le store est le résolveur du dépôt (`SaveFarmNameResolver`, …). Le VM
/// ne conformait le protocole que pour déléguer à `L(_:)` — la conformité
/// vit désormais là où vit la résolution.
extension LocalizationStore: L10nResolver {
    func localized(_ key: String) -> String { localizedString(for: key) }
}

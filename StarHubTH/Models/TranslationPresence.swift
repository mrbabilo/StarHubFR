import Foundation

/// Ce que le parc sait d'une traduction posée sur un mod : y en a-t-il une, et
/// en existe-t-il une version plus récente.
///
/// Les deux règles vivaient **en double exemplaire** dans le ViewModel —
/// `translationUpdateAvailable` et `addonUpdateAvailable` portaient la même
/// comparaison, et le test de présence réimplémentait à la main ce que
/// `I18nLocaleResolver` sait déjà faire. Deux copies d'une même règle divergent
/// à la première retouche : c'est le constat d'`isOsJunk` (quatre copies dont
/// une amputée) et de X45.
public enum TranslationPresence {

    /// La mise à jour d'une ligne installée, s'il y en a une.
    ///
    /// **Sur les dates Nexus, jamais sur les numéros de version** : beaucoup de
    /// traducteurs reprennent le numéro du mod traduit, ou ne le bougent pas.
    ///
    /// - Parameters:
    ///   - amongAvailable: les résultats encore proposés.
    ///   - andInstalled: ceux qu'on a **retirés** des propositions parce
    ///     qu'ils correspondent à ce qui est déjà en place. C'est dans cette
    ///     moitié-là que vit, par nature, le résultat qui porte la mise à
    ///     jour — ne regarder que la première faisait disparaître la pastille.
    public static func update(for entry: InstalledTranslation,
                              amongAvailable available: [NexusModSearch.Hit],
                              andInstalled installed: [NexusModSearch.Hit])
        -> NexusModSearch.Hit? {
        // Sans identifiant, la ligne attend un rattachement : elle ne prétend
        // ni être à jour, ni être en retard.
        guard entry.nexusModId > 0 else { return nil }
        return (available + installed).first {
            $0.modId == entry.nexusModId
                && InstalledTranslationRegistry.isNewer($0.updatedAt, than: entry.updatedAt)
        }
    }

    /// `true` quand le dossier d'un mod porte une traduction française **que
    /// SMAPI servira**.
    ///
    /// Passe par `I18nLocaleResolver`, qui reproduit `SCore.GetTranslationFiles`
    /// lu à la source — layouts A et B, et la règle « la racine gagne,
    /// entièrement » : un seul `.json` à la racine suffit à faire ignorer tous
    /// les sous-dossiers, pour toutes les locales. La copie du ViewModel
    /// testait `i18n/fr.json` puis `i18n/fr/*.json` sans cette règle, et
    /// aurait donc annoncé une traduction que le jeu ne charge jamais. Aucun
    /// mod du parc n'était dans ce cas (mesuré le 2026-09-11).
    ///
    /// - Parameter modDirectory: le dossier **physique** du mod — un mod en
    ///   pause vit dans `Mods/.X`.
    public static func hasFrench(inModDirectory modDirectory: URL,
                                 fileManager: FileManager = .default) -> Bool {
        let i18n = modDirectory.appendingPathComponent("i18n", isDirectory: true)
        return !I18nLocaleResolver.files(in: i18n, locale: "fr",
                                         fileManager: fileManager).isEmpty
    }
}

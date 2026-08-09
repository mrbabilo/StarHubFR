import Foundation

/// L'anglais d'un mod a-t-il été touché **après** son français ?
///
/// C'est un soupçon, pas un constat : l'auteur a pu retoucher son fichier sans
/// changer une phrase. Le libellé qui en découle doit donc énoncer le fait et
/// ses deux dates, jamais un verdict.
///
/// C'est aussi le seul signal disponible le premier jour. Les archives de mods
/// conservent les dates de l'auteur : sur le parc réel, **21 dossiers `i18n`
/// ont un anglais plus récent que leur français, répartis sur 18 mods** (un
/// mod multi-composants pèse pour plusieurs dossiers), jusqu'à 454 jours
/// d'écart. La référence par clé (`TranslationBaseline`) est plus juste, mais
/// elle ne peut rien dire avant la première mise à jour qui suit son adoption.
public enum TranslationFreshness {
    /// Un écart mesuré : l'anglais est postérieur au français de `gap` secondes.
    public struct Staleness: Equatable, Sendable {
        /// Le composant concerné, `nil` pour un mod à un seul dossier `i18n`.
        public let component: String?
        public let sourceDate: Date
        public let targetDate: Date

        public init(component: String?, sourceDate: Date, targetDate: Date) {
            self.component = component
            self.sourceDate = sourceDate
            self.targetDate = targetDate
        }

        public var gap: TimeInterval { sourceDate.timeIntervalSince(targetDate) }
    }

    /// En deçà de cette marge, l'écart ne veut rien dire : 55 paires du parc
    /// partagent leur horodatage à la seconde près — des mods installés par
    /// copie, dont tous les fichiers portent la date de la copie.
    static let margin: TimeInterval = 60

    /// Le plus grand écart où l'anglais est postérieur, ou `nil`.
    ///
    /// Un mod à plusieurs composants est suspect dès qu'un seul l'est ; c'est
    /// le pire écart qui est rendu, avec le composant qui le porte.
    public static func staleness(forModAt modDirectory: URL, locale: String,
                                 fileManager: FileManager = .default) -> Staleness? {
        let directories = I18nLocaleResolver.i18nDirectories(inModDirectory: modDirectory,
                                                             fileManager: fileManager)
        let isMultiComponent = directories.count > 1
        var worst: Staleness?

        for directory in directories {
            // Les fichiers passent par le résolveur : une locale peut être
            // éclatée en plusieurs fichiers, et la source s'appeler `en.json`.
            guard let source = newestDate(of: sourceFiles(in: directory, fileManager: fileManager),
                                          fileManager: fileManager),
                  let target = newestDate(of: I18nLocaleResolver.files(in: directory,
                                                                       locale: locale,
                                                                       fileManager: fileManager),
                                          fileManager: fileManager)
            else { continue }
            guard source.timeIntervalSince(target) > margin else { continue }
            let candidate = Staleness(
                component: isMultiComponent
                    ? TranslationCoverage.componentLabel(of: directory, under: modDirectory)
                    : nil,
                sourceDate: source,
                targetDate: target)
            if worst == nil || candidate.gap > worst!.gap { worst = candidate }
        }
        return worst
    }

    /// Les fichiers de la langue source. `default` d'abord — c'est le nom que
    /// SMAPI attend — et `en` en repli, que certains auteurs emploient.
    private static func sourceFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        let byDefault = I18nLocaleResolver.files(in: directory, locale: "default",
                                                  fileManager: fileManager)
        guard byDefault.isEmpty else { return byDefault }
        return I18nLocaleResolver.files(in: directory, locale: "en", fileManager: fileManager)
    }

    private static func newestDate(of files: [URL], fileManager: FileManager) -> Date? {
        files.compactMap {
            (try? fileManager.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }.max()
    }
}

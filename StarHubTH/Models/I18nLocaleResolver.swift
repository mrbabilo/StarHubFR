import Foundation

/// Quels fichiers composent une locale dans un dossier `i18n/`.
///
/// Un mod range ses traductions de deux façons, et SMAPI accepte les deux :
/// - **layout A**, le cas courant — `i18n/fr.json` ;
/// - **layout B** — `i18n/fr/dialogue.json`, `i18n/fr/items.json`…
///
/// Composer `i18n/<langue>.json` à la main revient donc à afficher « pas de
/// traduction » sur un mod traduit. Sur la modlist de référence, 542 dossiers
/// `i18n/` sont en layout A et **6 en layout B**, dont quatre traduits en
/// français : `.Merchant`, `East Scarp NPCs`, `[CP] Button's Extra Books`,
/// `Hootin' & Hollerin'`.
///
/// Les règles ci-dessous reproduisent `SCore.GetTranslationFiles` et
/// `ReadTranslationFiles`, lus dans les sources de SMAPI le 2026-08-02 — pas
/// déduits d'une documentation.
enum I18nLocaleResolver {
    /// Les locales que ce dossier fournit réellement, pliées en minuscules.
    /// `default` en fait partie : c'est la locale de repli de SMAPI, et la
    /// traduire en « anglais » est une convention d'affichage qui appartient à
    /// l'appelant, pas au chargeur.
    static func locales(in i18nDirectory: URL, fileManager: FileManager = .default) -> [String] {
        let rootLocales = jsonFiles(in: i18nDirectory, fileManager: fileManager)
            .map { fold($0.deletingPathExtension().lastPathComponent) }
        // La racine l'emporte entièrement : voir `files(in:locale:)`.
        guard rootLocales.isEmpty else { return Set(rootLocales).sorted() }

        let subLocales = subdirectories(of: i18nDirectory, fileManager: fileManager)
            .filter { !jsonFiles(in: $0, fileManager: fileManager).isEmpty }
            .map { fold($0.lastPathComponent) }
        return Set(subLocales).sorted()
    }

    /// Les fichiers à lire pour une locale, triés par nom.
    ///
    /// **La racine gagne, entièrement.** SMAPI énumère les `*.json` de la racine
    /// avant les sous-dossiers ; dès qu'un fichier de sous-dossier suit un
    /// fichier racine, il enregistre une erreur et **interrompt la boucle**. Un
    /// seul `.json` à la racine suffit donc à faire ignorer *tous* les
    /// sous-dossiers, pour toutes les locales. Il n'y a pas de fusion mixte —
    /// s'attendre à en trouver une était une erreur de notre plan initial.
    ///
    /// Le tri par nom est une **divergence assumée** : SMAPI suit l'ordre du
    /// système de fichiers, non spécifié. À clé égale entre deux fichiers d'une
    /// même locale, SMAPI garde la première rencontrée ; nous rendons ce choix
    /// déterministe plutôt que dépendant du disque.
    static func files(in i18nDirectory: URL, locale: String,
                      fileManager: FileManager = .default) -> [URL] {
        let wanted = fold(locale)

        let root = jsonFiles(in: i18nDirectory, fileManager: fileManager)
        guard root.isEmpty else {
            return root
                .filter { fold($0.deletingPathExtension().lastPathComponent) == wanted }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        let directories = subdirectories(of: i18nDirectory, fileManager: fileManager)
        guard let match = directories.first(where: { fold($0.lastPathComponent) == wanted }) else {
            return []
        }
        return jsonFiles(in: match, fileManager: fileManager)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Fusionne les entrées de plusieurs fichiers d'une même locale.
    /// À clé égale, **la première occurrence gagne** : c'est le `TryAdd` de
    /// `ReadTranslationFiles`, qui conserve l'entrée déjà présente et signale le
    /// doublon. La comparaison est exacte ici, comme la sienne ; l'insensibilité
    /// à la casse n'intervient qu'à la lecture (`TranslationCoverage.fold`).
    static func merge(_ entries: [[String: String]]) -> [String: String] {
        var merged: [String: String] = [:]
        for file in entries {
            for (key, value) in file where merged[key] == nil {
                merged[key] = value
            }
        }
        return merged
    }

    // MARK: - Détail

    /// `.ToLower().Trim()`, appliqué par SMAPI au nom du fichier comme du
    /// dossier. À ne pas confondre avec le pliage des *clés*, qui lui ne trime
    /// pas — voir `TranslationCoverage.fold`.
    private static func fold(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Le seul point de lecture du disque de ce type.
    ///
    /// `try?` est ici l'expression exacte de l'intention : un dossier `i18n/`
    /// absent, illisible ou remplacé par un fichier n'est pas une erreur à
    /// remonter — c'est un mod sans traduction, cas parfaitement ordinaire sur
    /// les 951 mods du parc. La seule autre écriture serait un `catch {}` vide,
    /// que les conventions réprouvent davantage.
    private static func contents(of directory: URL, fileManager: FileManager) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory,
                                              includingPropertiesForKeys: nil)) ?? []
    }

    private static func subdirectories(of directory: URL, fileManager: FileManager) -> [URL] {
        contents(of: directory, fileManager: fileManager)
            .filter { isDirectory($0, fileManager: fileManager) }
    }

    private static func jsonFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        contents(of: directory, fileManager: fileManager).filter {
            $0.pathExtension.lowercased() == "json" && !isDirectory($0, fileManager: fileManager)
        }
    }

    /// `fileExists(atPath:isDirectory:)` plutôt que `resourceValues` : même
    /// réponse, sans `try`, et c'est déjà la façon dont le reste du dépôt
    /// interroge le disque.
    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }
}

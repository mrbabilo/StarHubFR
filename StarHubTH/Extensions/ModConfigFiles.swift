import Foundation

/// Liste des fichiers de configuration et de traduction qu'un mod SMAPI peut
/// embarquer et qu'il faut préserver lors d'une mise à jour. Cette liste est
/// partagée entre la sauvegarde manuelle (`ModConfigBackupManager`) et la
/// conservation automatique lors d'une mise à jour (`ModZipInstaller`) afin de
/// garantir un comportement cohérent.
enum ModConfigFiles {
    /// `config.json` (réglages du mod) plus tous les fichiers de traduction
    /// que les mods SMAPI peuvent embarquer — correspond aux codes de langue
    /// `i18n/` de SMAPI (en, de, es, fr, hu, id, it, ja, ko, pl, pt, ru, th,
    /// tr, uk, zh) plus `default.json`.
    static let preservable: Set<String> = [
        "config.json",
        "default.json",
        "en.json", "de.json", "es.json", "fr.json", "hu.json", "id.json",
        "it.json", "ja.json", "ko.json", "pl.json", "pt.json", "ru.json",
        "th.json", "tr.json", "uk.json", "zh.json"
    ]

    /// Trouve récursivement, sous `modFolder`, tous les fichiers préservables
    /// (`config.json` + `i18n/*.json` — voir `preservable`). Retourne le
    /// **chemin relatif au dossier du mod** (ex. `"config.json"`,
    /// `"i18n/fr.json"`, `"Sub/i18n/default.json"`), pas seulement le nom.
    ///
    /// Le chemin relatif est indispensable : les fichiers de langue vivent sous
    /// `i18n/`, pas à la racine. Sans cela, le snapshot les cherche à la racine,
    /// ne les trouve jamais, et la traduction communautaire est perdue à chaque
    /// mise à jour avec backup (B4-T4 — 16 `fr.json` du parc de référence ne
    /// survivent qu'en sauvegarde). Voir `docs/DOMAINE.md` §5.
    ///
    /// Source unique pour la conservation à l'update (`ModZipInstaller`).
    /// `ModConfigBackupManager.findConfigFiles` est encore une copie parallèle
    /// à unifier ici : en l'état, le backup manuel aplatit les fichiers de langue
    /// et les restore à la racine du mod au lieu de `i18n/` (bug associé, à
    /// corriger séparément).
    static func preservableFiles(under modFolder: String) -> [(relativePath: String, url: URL)] {
        let fm = FileManager.default
        let baseURL = URL(fileURLWithPath: modFolder, isDirectory: true)
        guard let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let baseStd = baseURL.standardizedFileURL.path
        var found: [(relativePath: String, url: URL)] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard preservable.contains(name) else { continue }
            let fileStd = fileURL.standardizedFileURL.path
            // Boundary-safe : `hasPrefix` seul confondrait "Mod" et "ModX"
            // (cf. `ModFolderRepairer.relativePath`). Tous les fichiers
            // énumérés sont sous `baseURL`, donc le cas « hors du mod » ne
            // devrait pas se produire — gardé par robustesse.
            let relative: String
            if fileStd == baseStd {
                relative = name
            } else if fileStd.hasPrefix(baseStd + "/") {
                relative = String(fileStd.dropFirst(baseStd.count + 1))
            } else {
                continue
            }
            found.append((relative, fileURL.standardizedFileURL))
        }
        return found
    }
}

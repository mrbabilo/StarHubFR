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
}

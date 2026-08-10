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

    // MARK: - À l'échelle d'un mod

    /// Les codes de langue que SMAPI reconnaît. Un `.json` d'un dossier `i18n`
    /// qui n'en porte pas le nom n'est pas une traduction — un `content.json`
    /// égaré ne doit pas compter pour une langue.
    public static let knownLanguageCodes: Set<String> = [
        "en", "de", "es", "fr", "hu", "id", "it", "ja", "ko",
        "pl", "pt", "ru", "th", "tr", "uk", "zh",
        // Relevé sur le parc : 27 fichiers `vi.json` ne comptaient pour rien.
        "vi",
    ]

    /// La langue de base d'une locale : `pt-br` → `pt`.
    ///
    /// **N'intervient plus dans `languageCodes`.** `Translator.GetRelevantLocales`
    /// remonte bien de variante en variante à l'exécution, mais ça remonte une
    /// chaîne de *traductions déjà chargées* — pas de *fichiers sur le disque*.
    /// Le chargeur, lui, n'ouvre que des fichiers dont le nom **est** un code
    /// connu : `pt-BR.json` n'est jamais lu, même si `pt.json` existe à côté.
    /// Compter `pt-br` pour `pt` ici afficherait une traduction que SMAPI ne
    /// sert jamais.
    ///
    /// Sert uniquement à `unloadableLocaleFiles`, pour proposer le nom que
    /// l'auteur aurait dû donner à son fichier quand on peut le déduire.
    ///
    /// Une locale qui n'est la variante d'aucune langue connue — un dossier
    /// `French/`, par exemple, ou `zh_old` — n'a pas de nom de repli déductible :
    /// renvoie `nil`.
    static func baseLanguage(of locale: String) -> String? {
        var candidate = locale
        while true {
            if knownLanguageCodes.contains(candidate) { return candidate }
            guard let dash = candidate.lastIndex(of: "-"), dash != candidate.startIndex
            else { return nil }
            candidate = String(candidate[candidate.startIndex..<dash])
        }
    }

    /// Jusqu'où descendre pour trouver les dossiers `i18n` d'un mod.
    ///
    /// Mesuré sur le parc de référence : 423 dossiers `i18n` sont à un niveau
    /// du dossier de mod, **121 à deux** (un content pack range son `i18n` sous
    /// `[CP] Nom/`), 6 à trois et **1 à quatre**. S'arrêter plus haut perd des
    /// mods réels — c'est exactement la faute que ce code corrige.
    public static let maxModDepth = 4

    /// Tous les dossiers `i18n` d'un mod, dans l'ordre de parcours.
    ///
    /// Rendus **séparément**, à dessein : pour la couverture, chaque dossier est
    /// une unité avec son propre `default.json` au dénominateur. Les fusionner
    /// calculerait un pourcentage qui ne correspond à aucun fichier réel.
    public static func i18nDirectories(inModDirectory modDirectory: URL,
                                       maxDepth: Int = maxModDepth,
                                       fileManager: FileManager = .default) -> [URL] {
        var found: [URL] = []
        var frontier = [modDirectory]
        for _ in 0..<maxDepth {
            var next: [URL] = []
            for directory in frontier {
                for child in subdirectories(of: directory, fileManager: fileManager) {
                    if child.lastPathComponent.lowercased() == "i18n" {
                        found.append(child)
                    } else {
                        next.append(child)
                    }
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return found
    }

    /// Les langues qu'un mod fournit, **tous ses dossiers `i18n` confondus**.
    ///
    /// L'union est la bonne opération ici : un mod est traduit en français dès
    /// qu'un de ses composants l'est. C'est l'inverse de la couverture, qui doit
    /// garder les unités séparées — voir `i18nDirectories(inModDirectory:)`.
    ///
    /// `default` est rendu comme `en` : c'est la locale de repli de SMAPI, qui
    /// porte l'anglais de référence.
    ///
    /// **Une variante régionale seule ne compte pour rien.** Le jeu ne charge
    /// que des codes nus — `pt.json`, pas `pt-BR.json` — donc un `pt-BR.json`
    /// sans `pt.json` à côté n'est jamais lu, quoi qu'annonce son nom. Mesuré
    /// sur le parc : 26 fichiers de ce genre, dont 16 `pt-BR.json`, ne
    /// contribuent donc plus ici. Ils restent signalés séparément par
    /// `unloadableLocaleFiles`.
    public static func languageCodes(inModDirectory modDirectory: URL,
                                     maxDepth: Int = maxModDepth,
                                     fileManager: FileManager = .default) -> [String] {
        var codes = Set<String>()
        for directory in i18nDirectories(inModDirectory: modDirectory,
                                         maxDepth: maxDepth, fileManager: fileManager) {
            for locale in locales(in: directory, fileManager: fileManager) {
                let resolved = (locale == "default") ? "en" : locale
                if knownLanguageCodes.contains(resolved) { codes.insert(resolved) }
            }
        }
        return codes.sorted()
    }

    /// Un fichier de traduction dont le nom n'est pas un code de langue que le
    /// jeu charge, avec le nom qu'il devrait porter quand on peut le déduire.
    public struct UnloadableLocaleFile: Equatable, Sendable {
        /// Tel qu'il est sur le disque — `"pt-BR.json"`, pas `"pt-br.json"`.
        public let fileName: String
        /// `"pt.json"` quand `baseLanguage(of:)` déduit un code de base absent
        /// du dossier ; `nil` quand aucun code n'est déductible (`zh_old.json`)
        /// **ou** que le fichier attendu existe déjà à côté (`fr-FR.json` à
        /// côté de `fr.json`) — dans ce dernier cas, proposer un nom serait
        /// absurde puisqu'il est déjà pris.
        public let expectedName: String?
    }

    /// Les fichiers de traduction qu'un mod fournit mais que le jeu n'ouvrira
    /// jamais, tous dossiers `i18n` confondus.
    ///
    /// Parcourt exactement les mêmes dossiers que `languageCodes` — même
    /// `i18nDirectories(inModDirectory:)` — mais rend l'information inverse :
    /// pas les langues qui marchent, les fichiers qui ne marchent pas.
    public static func unloadableLocaleFiles(inModDirectory modDirectory: URL,
                                             maxDepth: Int = maxModDepth,
                                             fileManager: FileManager = .default)
        -> [UnloadableLocaleFile] {
        var found: [UnloadableLocaleFile] = []
        for directory in i18nDirectories(inModDirectory: modDirectory,
                                         maxDepth: maxDepth, fileManager: fileManager) {
            found.append(contentsOf: unloadableFiles(in: directory, fileManager: fileManager))
        }

        var unique: [UnloadableLocaleFile] = []
        for file in found where !unique.contains(file) {
            unique.append(file)
        }
        return unique.sorted { $0.fileName < $1.fileName }
    }

    /// `default` et tout code de `knownLanguageCodes` : les seuls noms que le
    /// chargeur ouvre.
    private static func isLoadable(_ foldedName: String) -> Bool {
        foldedName == "default" || knownLanguageCodes.contains(foldedName)
    }

    /// Le nom de repli à proposer pour une locale illisible, ou `nil` s'il n'y
    /// en a pas — soit qu'aucun code de base ne s'en déduit, soit que ce code
    /// est déjà servi par une locale du même dossier.
    private static func expectedFileName(for foldedLocale: String,
                                         siblingLocales: Set<String>) -> String? {
        guard let base = baseLanguage(of: foldedLocale), !siblingLocales.contains(base) else {
            return nil
        }
        return "\(base).json"
    }

    /// Les fichiers illisibles d'un seul dossier `i18n`, layout A ou B — mêmes
    /// deux layouts que `locales(in:)`, avec la même règle : la racine
    /// l'emporte entièrement dès qu'elle contient un `.json`.
    private static func unloadableFiles(in i18nDirectory: URL,
                                        fileManager: FileManager) -> [UnloadableLocaleFile] {
        let root = jsonFiles(in: i18nDirectory, fileManager: fileManager)
        if !root.isEmpty {
            let siblings = Set(root.map { fold($0.deletingPathExtension().lastPathComponent) })
            return root.compactMap { file in
                let folded = fold(file.deletingPathExtension().lastPathComponent)
                guard !isLoadable(folded) else { return nil }
                return UnloadableLocaleFile(
                    fileName: file.lastPathComponent,
                    expectedName: expectedFileName(for: folded, siblingLocales: siblings))
            }
        }

        // Layout B : la locale est un sous-dossier. `locales(in:)` n'accepte
        // que ceux qui ont au moins un `.json` — un sous-dossier vide n'est
        // pas une locale, illisible ou pas.
        let directories = subdirectories(of: i18nDirectory, fileManager: fileManager)
            .filter { !jsonFiles(in: $0, fileManager: fileManager).isEmpty }
        let siblings = Set(directories.map { fold($0.lastPathComponent) })
        return directories.compactMap { directory in
            let folded = fold(directory.lastPathComponent)
            guard !isLoadable(folded) else { return nil }
            return UnloadableLocaleFile(
                fileName: directory.lastPathComponent,
                expectedName: expectedFileName(for: folded, siblingLocales: siblings))
        }
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
        // `.isDirectoryKey` est **préchargé** : sans lui, distinguer dossier et
        // fichier coûtait un appel système par entrée, soit 2,8 s de surcoût au
        // scan des 821 mods contre 1,3 s ici. Mesuré, pas supposé.
        (try? fileManager.contentsOfDirectory(at: directory,
                                              includingPropertiesForKeys: [.isDirectoryKey])) ?? []
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

    /// Lit l'attribut **déjà chargé** par `contents(of:)` — d'où l'absence
    /// d'appel disque supplémentaire ici. Un `fileExists(atPath:isDirectory:)`
    /// donnerait la même réponse mais en interrogeant le disque une seconde
    /// fois par entrée, ce qui doublait le coût du scan.
    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}

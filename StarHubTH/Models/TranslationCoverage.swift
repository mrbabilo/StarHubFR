import Foundation

/// Ce qui est réellement traduit dans un mod, et ce qui cloche pour le reste.
///
/// Le calcul compare les clés de l'anglais de référence (`default.json`) à
/// celles de la cible (`fr.json`). Il mesure **les clés explicitement traduites**,
/// pas « ce qui s'affichera en français en jeu » : une clé absente est servie en
/// anglais par SMAPI et rien n'est cassé. Les libellés doivent porter cette
/// distinction, sans quoi le hub crie au défaut là où il n'y en a pas.
///
/// Trois états, trois vécus différents pour le joueur :
/// - **manquante** — l'anglais s'affiche, le jeu marche ;
/// - **vide** — SMAPI ne retombe **pas** sur `default.json` (`GetRaw` a trouvé
///   la clé et retourne `""`), et affiche un texte de remplacement ;
/// - **blanche** (`"   "`) — pire encore : `HasValue()` teste `!IsNullOrEmpty`,
///   donc SMAPI affiche les espaces, c'est-à-dire rien, et **sans** le texte de
///   remplacement qui aurait signalé le problème.
///
/// Vide et blanche se comptent donc ensemble, et jamais avec les manquantes.
/// Vérifié dans `Framework/Translator.cs` et `Translation.cs`.
///
/// Inspiré de `scanner.rs` (Nana1873/stardew-i18n-translator, GPL) —
/// réimplémenté depuis son principe, aucun code repris. On lui reprend le
/// traitement des valeurs blanches et l'exclusion de `$schema` ; on écarte son
/// pliage de clés, qui applique un `trim` que SMAPI ne fait pas (voir `fold`).
public enum TranslationCoverage {
    /// Le résultat pour une paire source/cible.
    public struct Coverage: Equatable, Sendable {
        /// Clés de la source, hors `$schema`.
        public let total: Int
        /// Clés portant une traduction non vide.
        public let translated: Int
        /// Clés de la source absentes de la cible — l'anglais s'affiche.
        public let missing: [String]
        /// Clés présentes mais vides ou blanches — l'affichage est cassé.
        public let empty: [String]
        /// Clés de la cible que la source ne connaît pas.
        public let orphan: [String]
        /// Clés traduites dont la valeur est identique à l'anglais : légitime
        /// pour un nom propre, suspect sinon. Comptées comme traduites.
        public let identicalToSource: [String]

        public var percent: Double {
            total == 0 ? 0 : Double(translated) / Double(total) * 100
        }

        /// Le nombre à afficher, en pourcentage entier.
        ///
        /// Arrondi **vers le bas**, avec deux garde-fous : « 100 » n'est rendu
        /// que si tout est traduit — annoncer un travail terminé alors qu'il
        /// manque une clé sur mille est le seul arrondi que ce badge ne peut
        /// pas se permettre — et un début de traduction n'est jamais ramené à
        /// « 0 », qui le ferait passer pour rien du tout.
        public var displayPercent: Int {
            guard total > 0, translated > 0 else { return 0 }
            guard translated < total else { return 100 }
            return max(1, min(99, Int(percent.rounded(.down))))
        }

        public init(total: Int, translated: Int, missing: [String], empty: [String],
                    orphan: [String], identicalToSource: [String]) {
            self.total = total
            self.translated = translated
            self.missing = missing
            self.empty = empty
            self.orphan = orphan
            self.identicalToSource = identicalToSource
        }
    }

    /// Calcule la couverture de `target` au regard de `source`.
    public static func compute(source: [String: String],
                               target: [String: String]) -> Coverage {
        let targetByFolded = foldedLookup(target)
        let sourceFolded = Set(source.keys.filter(isCounted).map(fold))

        var translated = 0
        var missing: [String] = []
        var empty: [String] = []
        var identical: [String] = []

        for (key, sourceValue) in source where isCounted(key) {
            guard let targetValue = targetByFolded[fold(key)] else {
                missing.append(key)
                continue
            }
            if isBlank(targetValue) {
                empty.append(key)
            } else {
                translated += 1
                if targetValue == sourceValue { identical.append(key) }
            }
        }

        let orphan = target.keys
            .filter { isCounted($0) && !sourceFolded.contains(fold($0)) }
            .sorted()

        return Coverage(total: source.keys.filter(isCounted).count,
                        translated: translated,
                        missing: missing.sorted(),
                        empty: empty.sorted(),
                        orphan: orphan,
                        identicalToSource: identical.sorted())
    }

    /// Une rangée du diff EN/FR : clé, valeur anglaise, valeur française, état.
    public struct DiffRow: Equatable, Sendable, Identifiable {
        public enum State: String, Sendable, CaseIterable {
            case translated, missing, empty, identicalToSource, orphan
        }
        public let key: String
        public let english: String
        public let french: String
        public let state: State
        /// Le composant d'où vient la clé, quand le mod en a plusieurs — `nil`
        /// pour un mod à un seul dossier `i18n`, le cas courant.
        ///
        /// Deux composants peuvent définir la même clé : ce sont **deux** lignes
        /// à traduire, avec chacune son anglais. Sans cette distinction, elles
        /// partageraient la même identité et la liste en perdrait une.
        public let component: String?
        /// Le commentaire sous lequel l'auteur a rangé cette clé dans son
        /// fichier **anglais** — « Config », « Dialogue locationnel ». C'est la
        /// seule structure fiable de ces fichiers ; l'anglais fait référence
        /// parce qu'un `fr.json` peut n'avoir aucun commentaire.
        public let section: String?
        /// Le rang de cette section dans l'ordre du fichier. Deux sections
        /// homonymes — 65 « Spring » dans Ridgeside — n'ont pas le même rang :
        /// c'est lui qui les distingue, jamais leur titre.
        public let sectionIndex: Int?

        public var id: String { component.map { "\($0)/\(key)" } ?? key }

        public init(key: String, english: String, french: String, state: State,
                    component: String? = nil, section: String? = nil,
                    sectionIndex: Int? = nil) {
            self.key = key
            self.english = english
            self.french = french
            self.state = state
            self.component = component
            self.section = section
            self.sectionIndex = sectionIndex
        }
    }

    /// Construit les rangées du diff en un seul passage sur les deux tables.
    ///
    /// Les clés de la source viennent d'abord, triées, puis les orphelines.
    /// *(Restituer l'ordre du fichier d'origine — ce que fait la référence en
    /// conservant l'ordre de lecture — demanderait que le parseur rende autre
    /// chose qu'un dictionnaire ; c'est un raffinement de phase 2.)*
    public static func diffRows(source: [String: String],
                                target: [String: String],
                                following outline: I18nOutline.Outline? = nil) -> [DiffRow] {
        let targetByFolded = foldedLookup(target)
        let sourceFolded = Set(source.keys.filter(isCounted).map(fold))

        var rows: [DiffRow] = []
        rows.reserveCapacity(source.count + target.count)

        // L'ordre du fichier quand on le connaît, l'alphabet sinon. Trier
        // alphabétiquement disperserait les sections de l'auteur : une clé
        // « alpha » de la dernière section remonterait au-dessus de la première.
        let sourceKeys = orderedSourceKeys(source, following: outline)

        for key in sourceKeys {
            let english = source[key] ?? ""
            guard let french = targetByFolded[fold(key)] else {
                rows.append(DiffRow(key: key, english: english, french: "", state: .missing))
                continue
            }
            if isBlank(french) {
                // État distinct de `.missing` : c'est celui qui casse réellement
                // l'affichage, donc celui que la vue doit montrer en premier.
                rows.append(DiffRow(key: key, english: english, french: french, state: .empty))
            } else {
                rows.append(DiffRow(key: key, english: english, french: french,
                                    state: french == english ? .identicalToSource : .translated))
            }
        }

        for key in target.keys.filter({ isCounted($0) && !sourceFolded.contains(fold($0)) }).sorted() {
            rows.append(DiffRow(key: key, english: "", french: target[key] ?? "", state: .orphan))
        }
        return rows
    }

    /// Les clés source dans l'ordre du fichier si la structure est connue,
    /// alphabétique sinon. Les clés que la structure ignore — un fichier
    /// illisible pour elle, une entrée ajoutée depuis — sont ajoutées à la fin
    /// plutôt que perdues.
    ///
    /// **Une clé, une rangée.** `outline.orderedKeys` porte **toutes** les
    /// occurrences d'une clé lue deux fois dans le fichier — du JSON à clés
    /// dupliquées, que Newtonsoft (donc le jeu) accepte. Mesuré sur
    /// `[CP] Tea` : `spring_23` y est défini sous « Seasonal + Day-Specific
    /// Dialogue » puis sous « Marriage Dialogue ». `I18nOutline` retient déjà
    /// la **dernière** occurrence pour `section(of:)` et `sectionIndex(of:)`
    /// — une simple écriture de dictionnaire, qui écrase les précédentes à
    /// chaque passage. La position de la clé dans cette liste doit suivre la
    /// même règle : la placer à sa première occurrence l'afficherait dans le
    /// bloc de la mauvaise section — précisément le défaut que ce
    /// dédoublonnage doit éviter, pas seulement déplacer.
    private static func orderedSourceKeys(_ source: [String: String],
                                          following outline: I18nOutline.Outline?)
        -> [String] {
        let counted = source.keys.filter(isCounted)
        guard let outline else { return counted.sorted() }
        let known = Set(counted)
        var lastOccurrence: [String: Int] = [:]
        for (position, key) in outline.orderedKeys.enumerated() where known.contains(key) {
            lastOccurrence[key] = position
        }
        var ordered = lastOccurrence.keys.sorted { lastOccurrence[$0]! < lastOccurrence[$1]! }
        let seen = Set(ordered)
        ordered.append(contentsOf: counted.filter { !seen.contains($0) }.sorted())
        return ordered
    }

    /// La couverture d'un **mod entier**, composants compris.
    ///
    /// Chaque dossier `i18n` est mesuré séparément — il a son propre
    /// `default.json` au dénominateur — puis les compteurs sont additionnés.
    /// Fusionner les dictionnaires de clés donnerait un pourcentage qui ne
    /// correspond à aucun fichier réel : deux composants définissant chacun une
    /// clé `a` font bien deux clés à traduire, pas une.
    ///
    /// Rend `nil` quand rien n'est mesurable — aucun `i18n`, ou aucun avec un
    /// `default.json`. Un pack de traduction pur (un `fr.json` sans source) n'a
    /// pas de dénominateur : il ne doit ni compter pour 0 %, ni fausser le
    /// total du mod.
    public static func coverage(forModAt modDirectory: URL, locale: String,
                                fileManager: FileManager = .default) -> Coverage? {
        var total = 0, translated = 0
        var missing: [String] = [], empty: [String] = []
        var orphan: [String] = [], identical: [String] = []
        var measuredAny = false

        for directory in I18nLocaleResolver.i18nDirectories(inModDirectory: modDirectory,
                                                            fileManager: fileManager) {
            guard let source = entries(of: "default", in: directory, fileManager: fileManager)
            else { continue }
            let target = entries(of: locale, in: directory, fileManager: fileManager) ?? [:]
            let part = compute(source: source, target: target)
            measuredAny = true
            total += part.total
            translated += part.translated
            missing += part.missing
            empty += part.empty
            orphan += part.orphan
            identical += part.identicalToSource
        }

        guard measuredAny else { return nil }
        return Coverage(total: total, translated: translated,
                        missing: missing.sorted(), empty: empty.sorted(),
                        orphan: orphan.sorted(), identicalToSource: identical.sorted())
    }

    /// Le diff d'un **mod entier**, ses composants restant distincts.
    ///
    /// Chaque dossier `i18n` est diffé contre son propre `default.json` — les
    /// fusionner produirait des rangées qui ne correspondent à aucun fichier, et
    /// perdrait une clé définie par deux composants. Les rangées sont groupées
    /// par composant, chacun trié par clé, pour que la vue puisse les séparer
    /// visuellement sans retrier.
    ///
    /// Le composant reste `nil` quand le mod n'a qu'un dossier `i18n`, le cas
    /// courant : afficher « i18n/ » sur chaque ligne d'un mod simple serait du
    /// bruit.
    public static func diffRows(forModAt modDirectory: URL, locale: String,
                                fileManager: FileManager = .default) -> [DiffRow] {
        let directories = I18nLocaleResolver.i18nDirectories(inModDirectory: modDirectory,
                                                             fileManager: fileManager)
        let isMultiComponent = directories.count > 1

        return directories
            .map { directory -> (label: String, rows: [DiffRow]) in
                let label = componentLabel(of: directory, under: modDirectory)
                guard let source = entries(of: "default", in: directory, fileManager: fileManager)
                else { return (label, []) }
                let target = entries(of: locale, in: directory, fileManager: fileManager) ?? [:]
                // L'ordre et les sections viennent du fichier **anglais** : il
                // fait référence, et un `fr.json` peut n'avoir aucun
                // commentaire. Un tri alphabétique disperserait les sections.
                let outline = sourceOutline(in: directory, fileManager: fileManager)
                let rows = diffRows(source: source, target: target, following: outline).map {
                    DiffRow(key: $0.key, english: $0.english, french: $0.french,
                            state: $0.state, component: isMultiComponent ? label : nil,
                            section: outline?.section(of: $0.key),
                            sectionIndex: outline?.sectionIndex(of: $0.key))
                }
                return (label, rows)
            }
            .sorted { $0.label < $1.label }
            .flatMap(\.rows)
    }

    /// La structure du fichier anglais : l'ordre de ses clés et ses sections.
    /// `nil` s'il n'est pas lisible — les rangées repassent alors par le tri
    /// alphabétique.
    private static func sourceOutline(in directory: URL,
                                      fileManager: FileManager) -> I18nOutline.Outline? {
        let files = I18nLocaleResolver.files(in: directory, locale: "default",
                                             fileManager: fileManager)
        // Un layout B éclate une locale en plusieurs fichiers ; leurs structures
        // se suivent dans l'ordre de lecture, déjà trié par nom.
        var keys: [String] = []
        var sections: [String: String] = [:]
        var ranks: [String: Int] = [:]
        // Chaque fichier recommence ses rangs à 0 : les décaler du nombre de
        // sections déjà vues, sinon deux sections distinctes partageraient une
        // identité et le repliage de l'une replierait l'autre.
        var offset = 0
        for file in files {
            guard let data = fileManager.contents(atPath: file.path),
                  let decoded = I18nFileDecoder.decode(data) else { continue }
            let outline = I18nOutline.read(decoded.text)
            keys.append(contentsOf: outline.orderedKeys)
            sections.merge(outline.sectionByKey) { first, _ in first }
            for (key, rank) in outline.sectionIndexByKey where ranks[key] == nil {
                ranks[key] = rank + offset
            }
            offset += (outline.sectionIndexByKey.values.max().map { $0 + 1 }) ?? 0
        }
        guard !keys.isEmpty else { return nil }
        return I18nOutline.Outline(orderedKeys: keys, sectionByKey: sections,
                                   sectionIndexByKey: ranks)
    }

    /// Le nom du composant : le dossier qui contient le `i18n`, relatif au mod.
    /// Pour `Mod/[CP] X/i18n` c'est `[CP] X` ; pour `Mod/i18n`, le nom du mod.
    private static func componentLabel(of i18nDirectory: URL, under modDirectory: URL) -> String {
        let parent = i18nDirectory.deletingLastPathComponent()
        return parent.path == modDirectory.path
            ? modDirectory.lastPathComponent
            : parent.lastPathComponent
    }

    /// Les entrées d'une locale dans un dossier `i18n`, fichiers fusionnés.
    /// `nil` si la locale n'y est pas, ou si aucun de ses fichiers n'est lisible.
    private static func entries(of locale: String, in directory: URL,
                                fileManager: FileManager) -> [String: String]? {
        let files = I18nLocaleResolver.files(in: directory, locale: locale,
                                             fileManager: fileManager)
        guard !files.isEmpty else { return nil }
        var parsed: [[String: String]] = []
        for file in files {
            // Depuis les octets : quatre fichiers du parc ne sont pas en
            // UTF-8, et le jeu les lit malgré tout (cf. `I18nFileDecoder`).
            guard let data = fileManager.contents(atPath: file.path),
                  let map = try? I18nLenientParser.parse(data)
            else { continue }
            parsed.append(map)
        }
        return parsed.isEmpty ? nil : I18nLocaleResolver.merge(parsed)
    }

    /// Pliage d'une clé pour la comparaison : **minuscules seulement**.
    ///
    /// SMAPI construit ses dictionnaires avec `StringComparer.OrdinalIgnoreCase`
    /// (`Translator.cs`) : insensible à la casse, **sensible aux espaces**.
    /// Trimer en plus — ce que fait la référence — apparierait `"key "` et
    /// `"key"`, que le jeu distingue : une clé serait comptée traduite alors
    /// qu'elle ne se chargera jamais. Le `.Trim()` qu'on trouve dans SMAPI porte
    /// sur la **locale**, pas sur les clés.
    ///
    /// C'est une approximation ASCII d'`OrdinalIgnoreCase` : `lowercased()` est
    /// Unicode et dépend de la locale, là où la comparaison C# est ordinale.
    /// Sans portée pour des clés i18n, mais autant ne pas prétendre à
    /// l'équivalence.
    public static func fold(_ key: String) -> String {
        key.lowercased()
    }

    // MARK: - Détail

    /// `$schema` est une annotation d'éditeur, pas une traduction. SMAPI la
    /// traite comme une clé ordinaire ; l'exclure est **notre convention**,
    /// partagée avec la référence, et il faut l'assumer : sans elle nos totaux
    /// différeraient des siens de un.
    private static func isCounted(_ key: String) -> Bool { key != "$schema" }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Table de la cible indexée par clé pliée. À collision de pliage, la
    /// première clé rencontrée gagne — comme la recherche de SMAPI, qui rend la
    /// première correspondance insensible à la casse.
    private static func foldedLookup(_ target: [String: String]) -> [String: String] {
        var lookup: [String: String] = [:]
        lookup.reserveCapacity(target.count)
        for key in target.keys.sorted() where lookup[fold(key)] == nil {
            lookup[fold(key)] = target[key]
        }
        return lookup
    }
}

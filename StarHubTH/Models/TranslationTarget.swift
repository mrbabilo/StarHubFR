import Foundation

/// **Où** une traduction s'écrit dans un dossier `i18n`, et pourquoi parfois
/// nulle part.
///
/// Cette décision vivait au milieu de `saveTranslation` (ViewModel), donc hors
/// de portée des tests, alors qu'elle est la plus dangereuse du domaine : un
/// seul `.json` posé à la racine d'un dossier rangé en **layout B** suffit à
/// faire ignorer *tous* ses sous-dossiers par SMAPI, pour toutes les locales
/// (voir `I18nLocaleResolver.files(in:locale:)`). Sur le parc de référence,
/// 7 dossiers `i18n` sont en layout B, **5 traduits en français** (mesuré le
/// 2026-09-11) : `.Merchant`, `East Scarp NPCs`, `[CP] Button's Extra Books`,
/// `Hootin' & Hollerin'`, `[CP] Sword & Sorcery`.
///
/// Le type ne décide que de la cible : il n'écrit rien. L'appelant garde
/// l'écriture, le journal et l'ouverture des droits (X7).
public enum TranslationTarget {

    /// Le fichier à écrire, la clé sous laquelle l'écrire, et la source qui
    /// donne son rang à une clé neuve.
    public struct Destination: Equatable, Sendable {
        /// Le fichier de la locale. **Peut ne pas exister encore** : c'est le
        /// cas d'une locale créée à la racine d'un dossier en layout A.
        public let file: URL
        /// La clé telle qu'elle doit être écrite — celle déjà présente dans le
        /// fichier si elle y est, sinon celle demandée. SMAPI compare ses clés
        /// en `OrdinalIgnoreCase` : réécrire `Greet` à côté d'un `greet`
        /// existant créerait un doublon que le jeu tranche sans nous.
        public let key: String
        /// Le fichier source (`default`) qui correspond à la cible.
        public let sourceFile: URL
        /// Son texte, déjà décodé — le parc porte des i18n en UTF-16 et UTF-32.
        public let sourceText: String

        public init(file: URL, key: String, sourceFile: URL, sourceText: String) {
            self.file = file
            self.key = key
            self.sourceFile = sourceFile
            self.sourceText = sourceText
        }
    }

    /// Pourquoi il n'y a pas de cible. Chaque cas porte de quoi le dire à
    /// l'utilisateur : `reason` est la phrase, en français, que l'appelant
    /// préfixe de son propre contexte — le journal de l'app n'est pas
    /// localisé, donc le texte EST la décision (patron `NexusResume`).
    public enum Refusal: Error, Equatable, Sendable {
        /// Aucun fichier `default` : rien ne donne le rang des clés, et le mod
        /// n'a de toute façon rien à traduire.
        case noSource(i18nPath: String)
        /// Layout B à plusieurs fichiers, et aucun ne porte déjà la clé :
        /// refuser plutôt qu'inventer la section (`fr/dialogue.json`,
        /// `fr/items.json`…) qui devrait l'accueillir.
        case keyAbsentFromEveryLocaleFile(key: String, locale: String,
                                          fileCount: Int, i18nPath: String)
        /// La locale n'existe pas et le dossier est en layout B : la créer à la
        /// racine ferait cesser la lecture des sous-dossiers existants.
        case localeWouldShadowLayoutB(locale: String, i18nPath: String)
        /// La source existe mais ne se lit pas.
        case unreadableSource(path: String)

        public var reason: String {
            switch self {
            case .noSource(let path):
                return "aucun default.json dans \(path)"
            case .keyAbsentFromEveryLocaleFile(let key, let locale, let count, let path):
                return "\(key) absente des \(count) fichiers de \(locale) dans \(path)"
            case .localeWouldShadowLayoutB(let locale, let path):
                return "\(locale) inexistante et \(path) est en layout B — créer un fichier "
                    + "à la racine casserait la lecture des sous-dossiers existants"
            case .unreadableSource(let path):
                return "\(path) illisible"
            }
        }
    }

    /// - Parameters:
    ///   - i18nDirectory: le dossier `i18n` du composant visé, déjà résolu par
    ///     `TranslationComponentResolver`.
    ///   - locale: le code de locale à écrire (`fr`).
    ///   - key: la clé, telle que la source la déclare.
    public static func resolve(inI18nDirectory i18nDirectory: URL,
                               locale: String,
                               key: String,
                               fileManager: FileManager = .default)
        -> Result<Destination, Refusal> {

        let sourceFiles = I18nLocaleResolver.files(in: i18nDirectory, locale: "default",
                                                   fileManager: fileManager)
        guard !sourceFiles.isEmpty else {
            return .failure(.noSource(i18nPath: i18nDirectory.path))
        }
        let localeFiles = I18nLocaleResolver.files(in: i18nDirectory, locale: locale,
                                                   fileManager: fileManager)

        let file: URL
        let realKey: String
        if !localeFiles.isEmpty {
            // La locale existe, sur un ou plusieurs fichiers. Quand la clé y est
            // déjà, on édite le fichier qui la porte — jamais un autre : y
            // écrire une clé absente créerait un doublon invisible en jeu.
            // `files(in:locale:)` rend ses fichiers triés par nom ; le premier
            // qui porte la clé l'emporte, comme `merge` le ferait à la lecture.
            let folded = TranslationCoverage.fold(key)
            var found: (file: URL, key: String)?
            for candidate in localeFiles {
                guard let data = fileManager.contents(atPath: candidate.path),
                      let text = I18nFileDecoder.decode(data)?.text,
                      let parsed = try? I18nLenientParser.parse(text) else { continue }
                if let match = parsed.keys.first(where: { TranslationCoverage.fold($0) == folded }) {
                    found = (candidate, match)
                    break
                }
            }
            if let found {
                file = found.file
                realKey = found.key
            } else if localeFiles.count == 1 {
                // Un seul fichier pour cette locale : aucune ambiguïté à
                // résoudre, layout A comme layout B à un seul composant. La clé
                // est neuve — le cas central de l'écran, une ligne « À
                // traduire » — donc écrite sous la casse de la source.
                file = localeFiles[0]
                realKey = key
            } else {
                return .failure(.keyAbsentFromEveryLocaleFile(key: key, locale: locale,
                                                        fileCount: localeFiles.count,
                                                        i18nPath: i18nDirectory.path))
            }
        } else {
            // La locale n'existe pas encore. La créer à la racine n'est
            // légitime que si le dossier n'est **pas** déjà en layout B — une
            // source en layout A vit dans `i18n` lui-même ; en layout B, dans
            // un sous-dossier `default/`.
            // ⚠️ Les chemins se comparent **résolus**. `contentsOfDirectory`
            // rend des URLs dont les liens symboliques sont suivis
            // (`/var/…` → `/private/var/…` sur macOS) : comparer les chaînes
            // brutes conclut « layout B » sur un dossier en layout A, et
            // refuse alors une traduction parfaitement légitime.
            let root = i18nDirectory.resolvingSymlinksInPath().path
            let sourceIsLayoutA = sourceFiles.allSatisfy {
                $0.deletingLastPathComponent().resolvingSymlinksInPath().path == root
            }
            guard sourceIsLayoutA else {
                return .failure(.localeWouldShadowLayoutB(locale: locale,
                                                    i18nPath: i18nDirectory.path))
            }
            file = i18nDirectory.appendingPathComponent("\(locale).json")
            realKey = key
        }

        // Le texte source correspondant : celui qui porte le même nom de
        // fichier que la cible choisie, à défaut le premier. Il ne sert qu'à la
        // garde de lisibilité et à l'ordre des clés *nouvelles* — une clé
        // trouvée ci-dessus a déjà son rang dans le fichier cible, et une
        // création en layout A n'a qu'un seul fichier source possible.
        let sourceFile = sourceFiles.first { $0.lastPathComponent == file.lastPathComponent }
            ?? sourceFiles[0]
        guard let sourceData = fileManager.contents(atPath: sourceFile.path),
              let sourceText = I18nFileDecoder.decode(sourceData)?.text else {
            return .failure(.unreadableSource(path: sourceFile.path))
        }

        return .success(Destination(file: file, key: realKey,
                                    sourceFile: sourceFile, sourceText: sourceText))
    }
}

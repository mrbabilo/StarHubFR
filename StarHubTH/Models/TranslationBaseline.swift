import Foundation

/// Ce que l'anglais et le français d'une clé disaient le jour où on les a vus
/// pour la première fois.
///
/// Sans cette référence, une traduction communautaire déjà présente sur le
/// disque ne pourrait **jamais** être signalée obsolète : on n'a rien à quoi la
/// comparer. C'est le mécanisme d'`imported_baselines` de
/// `stardew-i18n-translator`, à une différence près — eux enregistrent un
/// SHA-256 de l'anglais, nous la valeur elle-même. Quelques mégaoctets de plus,
/// et l'on peut montrer *ce que* la phrase disait plutôt que seulement affirmer
/// qu'elle a changé.
///
/// Vit dans Application Support et non dans Caches, comme
/// `ModErrorHistoryStore` : une référence perdue ne se reconstruit pas.
public enum TranslationBaseline {
    public struct Entry: Codable, Equatable, Sendable {
        /// La valeur anglaise au moment où la référence a été posée.
        public let source: String
        /// La valeur française alors présente. Sert à distinguer « l'anglais a
        /// changé » de « les deux ont changé, donc quelqu'un a retraduit ».
        public let target: String
        /// Le traducteur a explicitement accepté une divergence de marques pour
        /// **ce** couple source/cible — voir `TranslationWaiver`.
        ///
        /// Absent des fichiers écrits avant cette version : il décode alors à
        /// `false`, sans quoi les références déjà posées deviendraient
        /// illisibles, et avec elles la seule preuve qu'une traduction a été
        /// faite sur un anglais donné.
        public let tokenMismatchAccepted: Bool
        /// « Écrit sans être relu » : posé par la pré-traduction par lot
        /// uniquement (spec §2.4 — la voie par clé passe par un
        /// « Enregistrer » explicite, elle ne pose jamais le drapeau).
        /// Enregistrer la clé, modifiée ou non, le retire.
        ///
        /// Absent des sidecars écrits avant la P2b : il décode alors à
        /// `false`, comme `tokenMismatchAccepted` avant lui.
        public let reviewNeeded: Bool

        enum CodingKeys: String, CodingKey {
            case source, target, tokenMismatchAccepted, reviewNeeded
        }

        public init(source: String, target: String, tokenMismatchAccepted: Bool = false,
                    reviewNeeded: Bool = false) {
            self.source = source
            self.target = target
            self.tokenMismatchAccepted = tokenMismatchAccepted
            self.reviewNeeded = reviewNeeded
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = try container.decode(String.self, forKey: .source)
            target = try container.decode(String.self, forKey: .target)
            tokenMismatchAccepted =
                try container.decodeIfPresent(Bool.self, forKey: .tokenMismatchAccepted) ?? false
            reviewNeeded =
                try container.decodeIfPresent(Bool.self, forKey: .reviewNeeded) ?? false
        }
    }

    /// L'identité d'une clé dans un mod : son composant et son nom, séparés par
    /// un octet nul — en pratique, ni l'un ni l'autre n'en contient, mais rien
    /// ne le garantit par construction. Une simple concaténation collisionnerait
    /// (`"Aa"` + `""` == `"A"` + `"a"`) ; le séparateur l'évite tant qu'aucun des
    /// deux membres ne le porte lui-même.
    public static func key(component: String?, key: String) -> String {
        "\(component ?? "")\u{0}\(key)"
    }

    /// Le dossier du magasin. `nil` si Application Support est introuvable.
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first else { return nil }
        let dir = base
            .appendingPathComponent("StarHubTH", isDirectory: true)
            .appendingPathComponent("TranslationBaselines", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func load(modFolderName: String, in directory: URL,
                            fileManager: FileManager = .default) -> [String: Entry] {
        guard let data = fileManager.contents(atPath: fileURL(modFolderName, in: directory).path),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }

    /// Remplace le magasin d'un mod. Écriture atomique : une écriture
    /// interrompue laisserait un fichier tronqué, donc une référence perdue.
    public static func save(_ entries: [String: Entry], modFolderName: String,
                            in directory: URL,
                            fileManager: FileManager = .default) throws {
        let file = fileURL(modFolderName, in: directory)
        try fileManager.createDirectory(at: file.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: file, options: .atomic)
    }

    // MARK: - Drapeau « à relire » (lot P2b)

    /// Pose le drapeau « écrit sans être relu » pour une clé du mod (spec
    /// §2.4 : seul le lot le pose). L'entrée est créée s'il faut — les clés
    /// du lot n'ont jamais de référence, elles étaient vides ou absentes —
    /// et une entrée existante garde ses valeurs : le drapeau est une
    /// propriété de la clé, pas une réévaluation de sa référence.
    public static func setReviewNeeded(component: String?, key: String,
                                       source: String, target: String,
                                       modFolderName: String, in directory: URL,
                                       fileManager: FileManager = .default) throws {
        let id = Self.key(component: component, key: key)
        var entries = load(modFolderName: modFolderName, in: directory,
                           fileManager: fileManager)
        let existing = entries[id]
        entries[id] = Entry(source: existing?.source ?? source,
                            target: existing?.target ?? target,
                            tokenMismatchAccepted: existing?.tokenMismatchAccepted ?? false,
                            reviewNeeded: true)
        try save(entries, modFolderName: modFolderName, in: directory,
                 fileManager: fileManager)
    }

    /// Une clé à marquer « à relire », pour la forme plurielle.
    public struct ReviewFlag: Equatable, Sendable {
        public let component: String?
        public let key: String
        public let source: String
        public let target: String

        public init(component: String?, key: String, source: String, target: String) {
            self.component = component
            self.key = key
            self.source = source
            self.target = target
        }
    }

    /// Pose le drapeau sur plusieurs clés en **une** lecture et **une**
    /// écriture. Le lot en marque des centaines : appelée une par une, la
    /// forme singulière relit et réécrit tout le sidecar à chaque clé, et le
    /// fichier grossit au fil du lot — le coût devient quadratique, sur le
    /// thread principal, entre deux appels réseau.
    ///
    /// Mêmes règles que la forme singulière, entrée par entrée : ce qui
    /// existe garde ses valeurs. Une liste vide n'écrit rien — surtout pas un
    /// sidecar pour un lot qui n'a rien traduit.
    public static func setReviewNeeded(_ flags: [ReviewFlag],
                                       modFolderName: String, in directory: URL,
                                       fileManager: FileManager = .default) throws {
        guard !flags.isEmpty else { return }
        var entries = load(modFolderName: modFolderName, in: directory,
                           fileManager: fileManager)
        for flag in flags {
            let id = Self.key(component: flag.component, key: flag.key)
            let existing = entries[id]
            entries[id] = Entry(source: existing?.source ?? flag.source,
                                target: existing?.target ?? flag.target,
                                tokenMismatchAccepted: existing?.tokenMismatchAccepted ?? false,
                                reviewNeeded: true)
        }
        try save(entries, modFolderName: modFolderName, in: directory,
                 fileManager: fileManager)
    }

    /// Retire le drapeau — enregistrer la clé (modifiée ou non) la relit
    /// (spec §7). Sans entrée ou sans drapeau, ne fait rien : ce chemin
    /// sert aussi au cas ordinaire d'un enregistrement qui n'a jamais été
    /// touché par le lot.
    public static func clearReviewNeeded(component: String?, key: String,
                                         modFolderName: String, in directory: URL,
                                         fileManager: FileManager = .default) throws {
        let id = Self.key(component: component, key: key)
        var entries = load(modFolderName: modFolderName, in: directory,
                           fileManager: fileManager)
        guard let existing = entries[id], existing.reviewNeeded else { return }
        entries[id] = Entry(source: existing.source, target: existing.target,
                            tokenMismatchAccepted: existing.tokenMismatchAccepted,
                            reviewNeeded: false)
        try save(entries, modFolderName: modFolderName, in: directory,
                 fileManager: fileManager)
    }

    /// Les identités des clés « à relire », au même format que
    /// `TranslationCoverage.DiffRow.id` (`component/key`, ou `key`) : le
    /// badge du diff et son filtre comparent directement les deux.
    public static func reviewNeededRowIDs(modFolderName: String, in directory: URL,
                                          fileManager: FileManager = .default) -> Set<String> {
        let entries = load(modFolderName: modFolderName, in: directory,
                           fileManager: fileManager)
        // La clé du magasin est `component\u{0}key` (voir `key(component:key:)`) :
        // on repasse au séparateur lisible de `DiffRow.id`.
        return Set(entries.filter(\.value.reviewNeeded).keys.map { composite in
            let parts = composite.split(separator: "\u{0}", maxSplits: 1,
                                        omittingEmptySubsequences: false)
            guard parts.count == 2 else { return composite }
            let component = String(parts[0])
            return component.isEmpty ? String(parts[1]) : "\(component)/\(parts[1])"
        })
    }

    // MARK: - Index

    /// Protège l'intervalle lecture-modification-écriture de `updateIndex`, pas
    /// l'écriture seule — celle-ci est déjà atomique. Sans ce verrou, deux
    /// appels qui se croisent liraient tous deux l'index avant qu'aucun n'écrive,
    /// et le second effacerait la mise à jour du premier. Aujourd'hui l'appel
    /// vient de l'ouverture d'un onglet (donc séquentiel), mais rien ne
    /// l'empêchera d'être déclenché par un balayage sur tout le parc de mods.
    private static let indexLock = NSLock()

    /// Le nombre de clés obsolètes connues, par mod, au dernier calcul.
    ///
    /// Le filtre de la liste lit ce seul fichier : ouvrir un magasin par mod à
    /// chaque scan coûterait ~350 lectures pour un chiffre déjà calculé.
    public static func loadIndex(in directory: URL,
                                 fileManager: FileManager = .default) -> [String: Int] {
        guard let data = fileManager.contents(atPath: indexURL(in: directory).path),
              let index = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return index
    }

    public static func updateIndex(modFolderName: String, outdatedCount: Int, in directory: URL,
                                   fileManager: FileManager = .default) throws {
        indexLock.lock()
        defer { indexLock.unlock() }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var index = loadIndex(in: directory, fileManager: fileManager)
        index[modFolderName] = outdatedCount
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL(in: directory), options: .atomic)
    }

    /// Retire l'entrée d'un mod de l'index partagé — installation, mise à
    /// jour, restauration de sauvegarde.
    ///
    /// Sans cette fonction, `outdatedKeysByMod` ne pouvait être purgé qu'en
    /// mémoire côté ViewModel : le prochain `loadIndex` (au scan suivant, ou
    /// à l'ouverture d'un autre onglet Traduction) relisait l'ancien compte
    /// depuis `index.json` et le réinjectait, ramenant silencieusement la
    /// note et la place dans le filtre d'un mod pourtant réinstallé. La seule
    /// façon de rester juste quel que soit l'ordre des rechargements est de
    /// purger l'entrée **sur le disque**, pas seulement en mémoire.
    ///
    /// Même verrou que `updateIndex` : c'est la même séquence
    /// lecture-modification-écriture, elle court le même risque de
    /// croisement entre deux appels concurrents.
    public static func removeFromIndex(modFolderName: String, in directory: URL,
                                       fileManager: FileManager = .default) throws {
        indexLock.lock()
        defer { indexLock.unlock() }
        var index = loadIndex(in: directory, fileManager: fileManager)
        guard index.removeValue(forKey: modFolderName) != nil else { return }
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL(in: directory), options: .atomic)
    }

    /// Supprime le magasin d'un mod **et** son entrée dans l'index partagé —
    /// à appeler quand le mod lui-même disparaît, pas quand son contenu
    /// change (c'est `removeFromIndex`, seul, qui sert ce second cas via
    /// `invalidateFrenchCoverage`).
    ///
    /// Ce magasin a repris toutes les conventions de `ModErrorHistoryStore`
    /// sauf celle qui borne sa croissance : sans cette fonction, un mod
    /// désinstallé garde son fichier de références pour toujours. Sur
    /// `Ridgeside Village` à lui seul, 17 748 paires anglais/français.
    ///
    /// Réutilise `removeFromIndex` plutôt que de refaire sa logique de
    /// verrouillage — `NSLock` n'est pas réentrant, verrouiller ici puis
    /// entrer dans `removeFromIndex` interbloquerait. La suppression du
    /// fichier par mod, elle, n'a pas besoin du même verrou : chaque mod a le
    /// sien, sans cycle lecture-modification-écriture partagé qu'un appel
    /// concurrent pourrait croiser.
    public static func remove(modFolderName: String, in directory: URL,
                              fileManager: FileManager = .default) throws {
        try removeFromIndex(modFolderName: modFolderName, in: directory, fileManager: fileManager)
        let file = fileURL(modFolderName, in: directory)
        guard fileManager.fileExists(atPath: file.path) else { return }
        try fileManager.removeItem(at: file)
    }

    // MARK: - Détail

    /// Le nom de fichier d'un mod, réduit à son dernier composant de chemin :
    /// un nom porteur de `/` ou de `..` écrirait sinon hors du dossier.
    ///
    /// Rangé dans un sous-dossier `mods/`, séparé de `index.json` : sans cette
    /// séparation, un mod nommé `index` produirait le même chemin que l'index
    /// partagé, et l'écraserait — perdant silencieusement le décompte de tous
    /// les autres mods au prochain `loadIndex` (qui échouerait à décoder un
    /// magasin de clés comme un index de comptes, et rendrait `[:]`).
    private static func fileURL(_ modFolderName: String, in directory: URL) -> URL {
        let safe = (modFolderName as NSString).lastPathComponent
        return directory
            .appendingPathComponent("mods", isDirectory: true)
            .appendingPathComponent("\(safe.isEmpty ? "_" : safe).json")
    }

    private static func indexURL(in directory: URL) -> URL {
        directory.appendingPathComponent("index.json")
    }
}

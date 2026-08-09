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

        public init(source: String, target: String) {
            self.source = source
            self.target = target
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

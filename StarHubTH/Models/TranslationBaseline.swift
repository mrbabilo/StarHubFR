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
    /// un octet nul — un caractère qu'aucun des deux ne peut contenir.
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
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL(modFolderName, in: directory), options: .atomic)
    }

    // MARK: - Index

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
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var index = loadIndex(in: directory, fileManager: fileManager)
        index[modFolderName] = outdatedCount
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL(in: directory), options: .atomic)
    }

    // MARK: - Détail

    /// Le nom de fichier d'un mod, réduit à son dernier composant de chemin :
    /// un nom porteur de `/` ou de `..` écrirait sinon hors du dossier.
    private static func fileURL(_ modFolderName: String, in directory: URL) -> URL {
        let safe = (modFolderName as NSString).lastPathComponent
        return directory.appendingPathComponent("\(safe.isEmpty ? "_" : safe).json")
    }

    private static func indexURL(in directory: URL) -> URL {
        directory.appendingPathComponent("index.json")
    }
}

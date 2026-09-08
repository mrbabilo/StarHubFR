import Foundation

/// C2-T4 §6 — le **dernier** delta de clés de chaque mod, persisté par
/// `UniqueID`. Un fichier `<uniqueId>.json`, écrasé à chaque mise à jour :
/// c'est un panneau « ce que la dernière mise à jour a changé », pas un
/// historique. Le renommage de dossier n'y touche pas — la clé est
/// l'identité du mod, pas son chemin (pas de 13ᵉ surface folder-keyed).
public enum ModUpdateKeyDeltaStore {

    /// Le dossier du magasin. `nil` si Application Support est introuvable.
    /// Ne crée rien : la création appartient à `save`, pour ne pas déposer
    /// un dossier vide à chaque lecture de fiche.
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first else { return nil }
        return base
            .appendingPathComponent("StarHubTH", isDirectory: true)
            .appendingPathComponent("ModUpdateKeyDeltas", isDirectory: true)
    }

    static func fileURL(uniqueId: String, directory: URL) -> URL {
        directory.appendingPathComponent("\(uniqueId).json")
    }

    /// Le delta persisté du mod, ou nil (absent, dossier indisponible,
    /// fichier illisible — silence voulu, l'absence est l'état ordinaire).
    public static func load(uniqueId: String, directory: URL?) -> ModUpdateKeyDelta? {
        guard let directory else { return nil }
        guard let data = FileManager.default.contents(atPath: fileURL(uniqueId: uniqueId, directory: directory).path)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ModUpdateKeyDelta.self, from: data)
    }

    /// Remplace le delta du mod. `directory == nil` : silence (l'appelant
    /// journalise) — on ne perd jamais l'installation pour un store.
    public static func save(_ delta: ModUpdateKeyDelta, directory: URL?) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(delta)
        try data.write(to: fileURL(uniqueId: delta.uniqueId, directory: directory),
                       options: .atomic)
    }

    /// Le mod n'existe plus : son delta non plus.
    public static func remove(uniqueId: String, directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: fileURL(uniqueId: uniqueId, directory: directory))
    }

    /// Plusieurs mods perdent leur delta d'un coup — supprimer un pack
    /// emporte ses composants. Les identifiants vides sont ignorés : une
    /// en-tête de groupe n'en a pas (`""` au scan), et les viser construirait
    /// un chemin « .json » qui ne devrait jamais exister.
    public static func removeAll(uniqueIds: [String], directory: URL?) {
        for uniqueId in uniqueIds where !uniqueId.isEmpty {
            remove(uniqueId: uniqueId, directory: directory)
        }
    }
}

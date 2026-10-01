import Foundation

/// D5-C — l'historique des mesures par mod, conservé par l'app : il survit à
/// la purge des fichiers de la sonde (qui ne tronque jamais). Une source
/// s'intègre **une fois** : relire les mêmes fichiers n'ajoute rien (le piège
/// « état qui s'accumule d'une exécution à l'autre »).
public struct ModImpactHistory: Codable, Equatable, Sendable {
    public static let maxSamplesPerVersion = 30
    public static let fileName = "ModImpactHistory.json"

    /// Sources déjà intégrées, par identifiant, à leur date.
    public private(set) var integrated: [String: Date] = [:]
    /// Par identifiant de mod **en minuscules**, du plus ancien au plus récent.
    public private(set) var samples: [String: [ModImpactSample]] = [:]
    /// Le coût de la sonde en jeu à la dernière source qui l'a mesuré.
    public private(set) var probeMsPerFrame: Double?
    /// Démarrages du Mac vus par l'app (`kern.boottime`) : le premier
    /// lancement après **chacun** est froid, pas seulement après le dernier.
    public private(set) var boots: [Date] = []
    /// Forme du fichier ; les champs absents prennent leur valeur par défaut.
    public private(set) var schema = 1

    public init() {}

    private enum CodingKeys: String, CodingKey { case schema, integrated, samples, probeMsPerFrame, boots }

    /// Tolérant : un champ absent (fichier d'une version antérieure) ou
    /// inconnu (version future) ne rend jamais l'historique illisible — un
    /// historique illisible n'est plus jamais réécrit.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        integrated = try c.decodeIfPresent([String: Date].self, forKey: .integrated) ?? [:]
        samples = try c.decodeIfPresent([String: [ModImpactSample]].self, forKey: .samples) ?? [:]
        probeMsPerFrame = try c.decodeIfPresent(Double.self, forKey: .probeMsPerFrame)
        boots = try c.decodeIfPresent([Date].self, forKey: .boots) ?? []
    }

    public mutating func noteBoot(_ boot: Date) {
        guard !boots.contains(boot) else { return }
        boots.append(boot)
        boots.sort()
    }

    /// Faux si la source était déjà là. Les échantillons négligeables sont
    /// gardés : les jeter tirait la médiane vers le haut (revue finale C1).
    @discardableResult
    public mutating func integrate(_ source: ModImpactSource) -> Bool {
        guard integrated[source.id] == nil else { return false }
        integrated[source.id] = source.date
        if let probe = source.probeMsPerFrame { probeMsPerFrame = probe }
        for (modId, sample) in source.samples {
            let key = modId.lowercased()
            var list = samples[key, default: []]
            list.append(sample)
            list.sort { $0.date < $1.date }
            let same = list.indices.filter { list[$0].version == sample.version && list[$0].kind == sample.kind }
            if same.count > Self.maxSamplesPerVersion, let oldest = same.first { list.remove(at: oldest) }
            samples[key] = list
        }
        return true
    }

    public enum LoadResult: Equatable, Sendable { case absent, loaded(ModImpactHistory), unreadable }

    /// Un fichier présent mais illisible rend `.unreadable` : l'appelant ne
    /// le réécrit jamais (mêmes règles que `ProbeLoadOrder.sync`).
    public static func load(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        do {
            return .loaded(try JSONDecoder().decode(ModImpactHistory.self, from: Data(contentsOf: url)))
        } catch {
            return .unreadable
        }
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

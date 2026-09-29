import Foundation

/// `guided-plan.json` (D5-A) : écrit **et effacé** par l'app seule ; la sonde
/// le lit (`System.Text.Json`, clés PascalCase) et ne l'efface jamais.
public struct GuidedPlan: Codable, Equatable, Sendable {
    public var version: Int
    public var id: UUID
    public var name: String
    public var role: ProbeMeasurement.Role
    public var location: String
    public var pairedWith: UUID?
    public var createdAt: Date

    public init(version: Int = 1, id: UUID, name: String, role: ProbeMeasurement.Role, location: String,
                pairedWith: UUID?, createdAt: Date) {
        self.version = version
        self.id = id
        self.name = name
        self.role = role
        self.location = location
        self.pairedWith = pairedWith
        // À la seconde : `.iso8601` n'écrit pas les fractions, le plan relu
        // doit égaler le plan écrit.
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
    }

    enum CodingKeys: String, CodingKey {
        case version = "Version", id = "Id", name = "Name", role = "Role", location = "Location"
        case pairedWith = "PairedWith", createdAt = "CreatedAt"
    }

    public static func load(from url: URL) -> GuidedPlan? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(GuidedPlan.self, from: data)
        } catch {
            // Plan illisible : pas de plan. La sonde l'ignore aussi (spec D5-A).
            return nil
        }
    }

    /// Écriture atomique (fichier temporaire puis renommage) : la sonde ne lit
    /// jamais un plan à moitié écrit.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Efface le plan **s'il est encore celui-là** : un plan préparé entre la
    /// lecture et l'effacement survit. Toutes les écritures de l'app passent
    /// par le store, sur le fil principal : lecture et effacement ne se
    /// croisent jamais avec une préparation. Un échec d'effacement lève —
    /// l'écran ne doit pas dire « rien en attente » avec le plan sur disque.
    public static func remove(at url: URL, ifId id: UUID) throws {
        guard load(from: url)?.id == id else { return }
        try FileManager.default.removeItem(at: url)
    }
}

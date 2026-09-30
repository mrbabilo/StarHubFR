import Foundation

/// Benchmark automatique (spec 2026-09-30 §3) : une chauffe par côté (une
/// seule en « même état »), puis A et B alternés — une dérive de la machine
/// touche les deux côtés.
public enum BenchmarkSide: String, Codable, Sendable {
    case warmupA, warmupB, a, b

    /// Compté dans le verdict (les chauffes ne le sont jamais).
    public var counts: Bool { self == .a || self == .b }
    /// Joue l'état A (sinon l'état B).
    public var isA: Bool { self == .warmupA || self == .a }
}

public struct BenchmarkRun: Codable, Equatable, Sendable {
    public let id: String
    public let side: BenchmarkSide

    public init(id: String, side: BenchmarkSide) {
        self.id = id
        self.side = side
    }
}

public enum BenchmarkSequence {
    /// L'option 4 ne tranche pas sous deux sessions par côté.
    public static let minimumPerSide = 2
    public static let defaultPerSide = 3

    public static func runs(perSide: Int, sameState: Bool,
                            makeId: () -> String = { UUID().uuidString }) -> [BenchmarkRun] {
        let n = max(perSide, minimumPerSide)
        var sides: [BenchmarkSide] = sameState ? [.warmupA] : [.warmupA, .warmupB]
        for _ in 0..<n { sides += [.a, .b] }
        return sides.map { BenchmarkRun(id: makeId(), side: $0) }
    }
}

/// `benchmark-plan.json` : écrit **et effacé** par l'app seule ; la sonde le
/// lit (`System.Text.Json`, clés PascalCase) et l'ignore une fois expiré.
public struct BenchmarkPlanFile: Codable, Equatable, Sendable {
    /// Un plan oublié par une app tuée ne doit détourner aucun lancement manuel.
    public static let lifetime: TimeInterval = 600

    public var version: Int
    public var runId: String
    public var saveName: String
    public var expiresAt: Date

    public init(version: Int = 1, runId: String, saveName: String, expiresAt: Date) {
        self.version = version
        self.runId = runId
        self.saveName = saveName
        // À la seconde : `.iso8601` n'écrit pas les fractions.
        self.expiresAt = Date(timeIntervalSince1970: expiresAt.timeIntervalSince1970.rounded(.down))
    }

    enum CodingKeys: String, CodingKey {
        case version = "Version", runId = "RunId", saveName = "SaveName", expiresAt = "ExpiresAt"
    }

    /// Écriture atomique : la sonde ne lit jamais un plan à moitié écrit.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Absent : rien à faire. Un autre échec lève — l'écran ne doit pas dire
    /// « terminé » avec le plan sur disque.
    public static func remove(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

import Foundation

/// Une mesure propre : une fenêtre nommée, posée à la main par l'auteur.
public struct ProbeMeasurement: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var start: Date
    /// `nil` : mesure en cours (ou jamais terminée, voir `closeOpen`).
    public var end: Date?

    public init(id: UUID = UUID(), name: String, start: Date, end: Date?) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
    }
}

/// `ProbeMeasurements.json`. `directory: nil` : aucun dossier (rien à lire,
/// rien à écrire) ; l'app passe `defaultDirectory()`, les tests un dossier
/// temporaire — jamais le vrai Application Support.
public enum ProbeMeasurementsFile {
    public enum Loaded: Equatable, Sendable {
        case missing
        case unreadable
        case measurements([ProbeMeasurement])
    }

    static let fileName = "ProbeMeasurements.json"

    public static func defaultDirectory() -> URL? {
        AppSupport.directory?.appendingPathComponent("Probe", isDirectory: true)
    }

    static func url(_ directory: URL) -> URL { directory.appendingPathComponent(fileName) }

    public static func load(directory: URL?) -> Loaded {
        guard let directory,
              let data = FileManager.default.contents(atPath: url(directory).path)
        else { return .missing }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return .measurements(try decoder.decode([ProbeMeasurement].self, from: data)) }
        catch { return .unreadable }
    }

    /// Écriture atomique ; un fichier illisible est mis de côté
    /// (`ProbeMeasurements.unreadable-<date>.json`), jamais écrasé — même
    /// règle que `ModHistoryFile`. Dates à la seconde (`.iso8601`).
    public static func save(_ measurements: [ProbeMeasurement], directory: URL?,
                            now: Date = Date()) throws {
        guard let directory else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(directory)
        if case .unreadable = load(directory: directory) {
            let stamp = Int(now.timeIntervalSince1970)
            try fm.moveItem(at: destination,
                            to: directory.appendingPathComponent("ProbeMeasurements.unreadable-\(stamp).json"))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(measurements).write(to: destination, options: .atomic)
    }
}

public struct ProbeMeasurementSegment: Equatable, Sendable {
    public let measurement: ProbeMeasurement
    public let minutes: [ProbeMinute]
    /// Une coupure tombe dans la fenêtre : les minutes d'après sont exclues.
    public let crossedChangeAt: Date?
}

public enum ProbeMeasurementsLogic {
    /// Une mesure jamais terminée se clôt à la dernière minute de sa session
    /// (la première session dont le dernier relevé suit le début).
    public static func closeOpen(_ measurements: [ProbeMeasurement],
                                 sessions: ProbeSessions) -> [ProbeMeasurement] {
        let lastMinutes = sessions.sessions.compactMap { session in
            session.minutes.compactMap { ProbeDate.parse($0.at) }.max()
        }
        return measurements.map { measurement in
            guard measurement.end == nil,
                  let closing = lastMinutes.filter({ $0 >= measurement.start }).min()
            else { return measurement }
            var closed = measurement
            closed.end = closing
            return closed
        }
    }

    /// La mesure comme fenêtre sur les segments d'une session : ses minutes
    /// sont celles dont la fin tombe dans `[start, end]`, jusqu'à la première
    /// coupure traversée — les minutes d'après mélangent les deux états (spec
    /// « Mesure propre »).
    public static func segment(_ measurement: ProbeMeasurement,
                               segments: [ProbeSegment]) -> ProbeMeasurementSegment {
        let inWindow = { (date: Date) in
            date >= measurement.start && measurement.end.map { date <= $0 } != false
        }
        var minutes: [ProbeMinute] = []
        var crossed: Date?
        for (index, segment) in segments.enumerated() {
            minutes += segment.minutes.filter { ProbeDate.parse($0.at).map(inWindow) == true }
            // Le dernier segment finit à la dernière minute, pas à une
            // coupure : seules les fins des autres referment la mesure.
            if index < segments.count - 1, let cut = segment.end,
               cut > measurement.start, measurement.end.map({ cut <= $0 }) != false {
                crossed = cut
                break
            }
        }
        return ProbeMeasurementSegment(measurement: measurement, minutes: minutes,
                                       crossedChangeAt: crossed)
    }
}

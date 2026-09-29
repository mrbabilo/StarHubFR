import Foundation

/// Une mesure guidée (D5-A) : écrite par la sonde dans
/// `guided-measurements.jsonl`, avec les minutes qu'elle a gardées.
public struct ProbeMeasurement: Equatable, Identifiable, Sendable {
    public enum Outcome: String, Sendable { case stable, noisy, abandoned }
    public enum Role: String, Codable, Sendable { case before, after }

    public var id: UUID
    public var name: String
    public var start: Date
    public var end: Date?
    /// Les minutes gardées par la sonde. La fenêtre `start…end` contient aussi
    /// des minutes que la sonde a écartées (autre lieu, minute partielle…) et
    /// que les gardes de l'app garderaient : seules celles-ci comptent.
    public var keptAt: Set<Date>?
    public var outcome: Outcome?
    public var role: Role?
    public var pairedWith: UUID?
    public var location: String?

    public init(id: UUID = UUID(), name: String, start: Date, end: Date?, keptAt: Set<Date>? = nil,
                outcome: Outcome? = nil, role: Role? = nil, pairedWith: UUID? = nil, location: String? = nil) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.keptAt = keptAt
        self.outcome = outcome
        self.role = role
        self.pairedWith = pairedWith
        self.location = location
    }

    /// Close par la sonde (`stable` ou `noisy`) : le plan peut être effacé.
    public var isFinished: Bool { outcome == .stable || outcome == .noisy }
}

public struct ProbeMeasurementSegment: Equatable, Sendable {
    public let measurement: ProbeMeasurement
    public let minutes: [ProbeMinute]
    /// Une coupure tombe dans la fenêtre : les minutes d'après sont exclues.
    public let crossedChangeAt: Date?
}

public enum ProbeMeasurementsLogic {
    /// Une mesure jamais terminée se clôt à la dernière minute de sa session
    /// (la première session dont le dernier relevé suit le début). Celle de
    /// `runningSession` (la partie en cours, qui écrit encore) reste ouverte.
    public static func closeOpen(_ measurements: [ProbeMeasurement],
                                 sessions: ProbeSessions,
                                 runningSession: String? = nil) -> [ProbeMeasurement] {
        let lastMinutes = sessions.sessions.compactMap { session -> (id: String, last: Date)? in
            session.minutes.compactMap { ProbeDate.parse($0.at) }.max().map { (session.id, $0) }
        }
        return measurements.map { measurement in
            guard measurement.end == nil,
                  let closing = lastMinutes.filter({ $0.last >= measurement.start }).min(by: { $0.last < $1.last }),
                  closing.id != runningSession
            else { return measurement }
            var closed = measurement
            closed.end = closing.last
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

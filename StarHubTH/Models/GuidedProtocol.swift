import Foundation

/// Ce qu'une mesure guidée à préparer doit porter (D5-A).
public struct GuidedPlanDraft: Equatable, Sendable {
    public var name: String
    public var role: ProbeMeasurement.Role
    public var location: String
    public var pairedWith: UUID?

    public init(name: String, role: ProbeMeasurement.Role, location: String, pairedWith: UUID?) {
        self.name = name
        self.role = role
        self.location = location
        self.pairedWith = pairedWith
    }
}

public enum GuidedProtocolState: Equatable, Sendable {
    case idle
    case planPending(GuidedPlan)
    /// La dernière mesure close est un « avant » qu'aucune mesure ne désigne.
    case beforeDone(ProbeMeasurement)
}

public enum GuidedReadiness: Equatable, Sendable {
    case ready, missing, paused
    case outdated(String)
}

public enum GuidedProtocol {
    public static let probeId = "mrbabilo.StarHubFR.Probe"
    /// Lieux proposés dans la feuille, la Ferme d'abord (spec « Le lieu »).
    public static let locations = ["Farm", "FarmHouse", "Town", "Beach", "Forest", "Mountain"]
    public static let fallbackLocation = "Farm"

    /// Lieux de passage ou générés : un étage de mine ne se retrouve pas.
    public static func isExcluded(_ location: String?) -> Bool {
        guard let location, !location.isEmpty else { return true }
        return location.hasPrefix("UndergroundMine") || location.hasPrefix("VolcanoDungeon") || location == "Temp"
    }

    public static func safeLocation(_ location: String?) -> String {
        isExcluded(location) ? fallbackLocation : location!
    }

    /// Le lieu où le côté a le plus de minutes gardées (égalité : l'ordre alphabétique).
    public static func dominantLocation(of side: ProbeSide) -> String? {
        let counts = Dictionary(side.comparable.kept.compactMap(\.minute.location).map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Le lieu d'une mesure préparée par un geste de l'analyse : celui de la
    /// mesure guidée du côté comparé, sinon son lieu dominant, jamais un lieu exclu.
    public static func gestureLocation(for side: ProbeSide) -> String {
        safeLocation(side.measurement?.location ?? dominantLocation(of: side))
    }

    public static func state(plan: GuidedPlan?, measurements: [ProbeMeasurement]) -> GuidedProtocolState {
        if let plan { return .planPending(plan) }
        let finished = measurements.filter(\.isFinished)
        guard let last = finished.max(by: { $0.start < $1.start }), last.role == .before,
              !finished.contains(where: { $0.pairedWith == last.id })
        else { return .idle }
        return .beforeDone(last)
    }

    /// Lu dans la liste des mods (manifeste installé), pas dans le dernier
    /// inventaire, qui retarde d'un lancement.
    public static func readiness(probeVersion: String?, isEnabled: Bool) -> GuidedReadiness {
        guard let probeVersion else { return .missing }
        guard isEnabled else { return .paused }
        guard supportsGuidance(probeVersion) else { return .outdated(probeVersion) }
        return .ready
    }

    public static func supportsGuidance(_ version: String) -> Bool {
        let parts = version.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return false }
        let numbers = parts.compactMap { $0 } + [0, 0, 0]
        return (numbers[0], numbers[1], numbers[2]) >= (0, 5, 0)
    }
}

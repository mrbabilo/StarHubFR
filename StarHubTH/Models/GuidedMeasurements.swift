import Foundation

/// `guided-measurements.jsonl` (D5-A), écrit par la sonde : une ligne par
/// mesure close. Lecture tolérante : ligne coupée comptée, champ inconnu
/// ignoré. Pour un même plan, une fin `stable`/`noisy` l'emporte sur
/// `abandoned` (qui peut la précéder ou la suivre) ; sinon la dernière ligne.
public enum GuidedMeasurementsFile {
    struct Line: Decodable {
        let planId: String
        let name: String
        let role: String?
        let pairedWith: String?
        let location: String?
        let start: String?
        let end: String?
        let keptAt: [String]?
        let outcome: String
    }

    public static func decode(_ data: Data) -> (measurements: [ProbeMeasurement], unreadable: Int) {
        let (lines, unreadable) = ProbeJSON.lines(Line.self, from: data)
        var byId: [UUID: ProbeMeasurement] = [:]
        var order: [UUID] = []
        var skipped = 0
        for line in lines {
            guard let id = UUID(uuidString: line.planId),
                  let outcome = ProbeMeasurement.Outcome(rawValue: line.outcome)
            else { skipped += 1; continue }
            let kept = Set((line.keptAt ?? []).compactMap(ProbeDate.parse))
            // Abandonnée sans minute gardée : rien à montrer, pas une erreur.
            guard let start = line.start.flatMap(ProbeDate.parse) ?? kept.min() else { continue }
            let measurement = ProbeMeasurement(
                id: id, name: line.name, start: start, end: line.end.flatMap(ProbeDate.parse) ?? kept.max(),
                keptAt: kept, outcome: outcome, role: line.role.flatMap(ProbeMeasurement.Role.init(rawValue:)),
                pairedWith: line.pairedWith.flatMap(UUID.init(uuidString:)), location: line.location)
            if let existing = byId[id], existing.isFinished, !measurement.isFinished { continue }
            if byId[id] == nil { order.append(id) }
            byId[id] = measurement
        }
        return (order.compactMap { byId[$0] }, unreadable + skipped)
    }
}

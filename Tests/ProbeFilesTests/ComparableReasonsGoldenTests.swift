import Testing
import Foundation
@testable import StarHubTHCore

/// Référence partagée avec la sonde (C#, `ComparableGuardsParityTests`) :
/// pour chaque minute de la fixture, la raison que les gardes de l'app
/// donnent — sur la **session entière**, comme `ProbePerformance.sides`.
/// Si une règle change d'un côté, le test de l'autre côté rougit.
struct ComparableReasonsGoldenTests {
    struct Row: Codable, Equatable {
        let session: String
        let at: String
        let reason: String
    }

    static func rows() throws -> [Row] {
        let sessions = ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"), costs: nil)
        var rows: [Row] = []
        for session in sessions.sessions {
            let result = ProbeComparableMinutes.filter(session.minutes, costs: [])
            let reasons = Dictionary(result.excluded.map { ($0.minute.at, $0.reason.rawValue) },
                                     uniquingKeysWith: { first, _ in first })
            let ordered = session.minutes.sorted {
                (ProbeDate.parse($0.at) ?? .distantPast) < (ProbeDate.parse($1.at) ?? .distantPast)
            }
            for minute in ordered {
                rows.append(Row(session: session.id, at: minute.at, reason: reasons[minute.at] ?? "kept"))
            }
        }
        return rows
    }

    @Test func goldenMatchesTheAppRules() throws {
        let golden = try JSONDecoder().decode([Row].self, from: try Fixture.data("comparable-reasons.json"))
        #expect(golden == (try Self.rows()))
        // La fixture exerce les six issues : sinon la référence ne prouve rien.
        #expect(Set(golden.map(\.reason))
                == ["kept", "unfocused", "title", "menuOpen", "night", "firstAfterTitle"])
    }

}

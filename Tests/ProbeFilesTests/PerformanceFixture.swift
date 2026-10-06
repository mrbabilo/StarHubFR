import Foundation
@testable import StarHubTHCore

enum PerformanceFixture {
    static func minute(index: Int, session: String = "A", location: String = "Farm",
                       frame: Double = 20, memory: Double? = 100,
                       scene: [String: Int]? = ["animals": 10]) throws -> ProbeMinute {
        var json: [String: Any] = [
            "Session": session, "At": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(index * 60))),
            "WallSeconds": 60, "Fps": 50, "InactiveTicks": 0, "Location": location,
            "FrameInterval": ["Count": 3000, "Avg": frame, "P50": frame, "P99": frame * 2, "Max": frame * 3],
            "Tick": ["Count": 3000, "Avg": 10, "P50": 10, "P99": 12, "Max": 15]
        ]
        if let memory { json["WorkingSetMB"] = memory }
        if let scene { json["Scene"] = scene }
        return try ProbeJSON.decoder().decode(ProbeMinute.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func side(_ id: String, session: String? = nil, start: Double? = nil, end: Double? = nil,
                     minutes: [ProbeMinute] = [], patches: [Bool?]? = nil,
                     inventory: [String: ProbeInventoryEntry]? = [:]) -> ProbeSide {
        ProbeSide(id: id, kind: .segment, session: session ?? id,
                  start: start.map(Date.init(timeIntervalSince1970:)),
                  end: end.map(Date.init(timeIntervalSince1970:)), minutes: minutes, costs: [], inventory: inventory,
                  comparable: ProbeComparableResult(kept: minutes.enumerated().map {
                      ProbeComparableMinute(minute: $0.element, patchesMeasured: patches == nil ? false : patches?[$0.offset])
                  }, exclusions: [:], excluded: []))
    }
}

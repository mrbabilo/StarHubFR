import Foundation

public enum ProbeImpactPresentation {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let version: String?
        public let currentVersionMeasured: Bool
        public let value: Double?
        public let sourceCount: Int
        public let lastMeasured: Date?
        public let coverage: Set<ModImpactAxis>
        public let axis: ModImpactAxis
    }
    public static func rows(entries: [ModImpactEntry], axis: ModImpactAxis) -> [Row] {
        entries.filter(\.isEnabled).map { entry in
            let stats = entry.shown
            let raw: Double?
            let count: Int
            switch axis {
            case .fps: raw = stats?.msPerFrame; count = stats?.inGameSources ?? 0
            case .spikes: raw = stats?.shares[.spikes].map { $0 * 100 }; count = stats?.inGameSources ?? 0
            case .launch: raw = stats?.launchMs; count = stats?.launchSources ?? 0
            case .save: raw = stats?.saveMs; count = stats?.saveSources ?? 0
            case .alloc: raw = stats?.allocMBPerMinute; count = stats?.inGameSources ?? 0
            }
            let value = raw.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            return Row(id: entry.id, name: entry.name, version: stats?.version,
                       currentVersionMeasured: entry.current != nil, value: value,
                       sourceCount: value == nil ? 0 : (stats?.measuredSources[axis] ?? count),
                       lastMeasured: value == nil ? nil : (stats?.measuredLast[axis] ?? stats?.last),
                       coverage: Set(stats?.shares.keys.map { $0 } ?? []), axis: axis)
        }.sorted {
            if ($0.value != nil) != ($1.value != nil) { return $0.value != nil }
            if $0.value != $1.value { return ($0.value ?? 0) > ($1.value ?? 0) }
            return $0.id < $1.id
        }
    }
}

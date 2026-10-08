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

/// D4-T6 — la mémoire retenue en textures, hors note : un stock que la sonde
/// relève quand `MeasureTextures` est allumé (sonde ≥ 0.9.24).
public enum ProbeTexturePresentation {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let version: String?
        public let currentVersionMeasured: Bool
        public let mb: Double
        public let sourceCount: Int
        public let lastMeasured: Date
    }

    /// Ce qui n'est rattaché à aucune ligne, à la dernière session relevée :
    /// `vanilla`, loaders joints par `+`, mods mis en pause ou désinstallés
    /// depuis. Montré, jamais jeté : la somme des lignes ne dit pas tout sans lui.
    public struct Remainder: Equatable, Sendable {
        public let mb: Double
        public let owners: [String]
        public let date: Date
    }

    /// Mods actifs relevés, du plus lourd au plus léger (départage :
    /// identifiant) ; la version affichée est celle de la fiche (`shown`).
    public static func rows(entries: [ModImpactEntry]) -> [Row] {
        entries.filter(\.isEnabled).compactMap { entry -> Row? in
            guard let stats = entry.shown, let mb = stats.textureMB, mb.isFinite, mb >= 0,
                  let last = stats.textureLast else { return nil }
            return Row(id: entry.id, name: entry.name, version: stats.version,
                       currentVersionMeasured: entry.current != nil, mb: mb,
                       sourceCount: stats.textureSources, lastMeasured: last)
        }
        .sorted { $0.mb != $1.mb ? $0.mb > $1.mb : $0.id < $1.id }
    }

    /// `shownIds` : les `UniqueID` des mods **actifs** (ceux qui ont une
    /// ligne), en minuscules.
    public static func remainder(history: ModImpactHistory, shownIds: Set<String>) -> Remainder? {
        let withTextures = history.samples.mapValues { $0.filter { $0.textureMB != nil } }
        guard let latest = withTextures.values.flatMap({ $0 }).map(\.date).max() else { return nil }
        var mb = 0.0
        var owners: [String] = []
        for (key, samples) in withTextures where !shownIds.contains(key) {
            guard let value = samples.last(where: { $0.date == latest })?.textureMB else { continue }
            mb += value
            owners.append(key)
        }
        return owners.isEmpty ? nil : Remainder(mb: mb, owners: owners.sorted(), date: latest)
    }
}

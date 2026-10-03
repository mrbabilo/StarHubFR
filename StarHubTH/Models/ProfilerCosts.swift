import Foundation

/// Le temps **propre** par mod et par événement, lu dans les lignes
/// `[RawLog] {json}` que Profiler (SinZ) écrit au journal SMAPI — D1-T2.
///
/// Forme relevée (journal du 2026-09-29, code de Profiler 2.0.0, §5 de
/// `docs/SOURCES.md`) : `[22:49:57 TRACE Profiler] [RawLog] {"OccuredAt":
/// 5000.7, "Metadata": {"Duration": 56.2, "ModId": …, "EventType": …,
/// "Details": …, "InnerDetails": [{"OccuredAt": …, "Metadata": {…}}]}}`.
/// La durée d'un nœud **inclut** ses enfants (le travail des autres mods
/// qu'il déclenche) : on la retire avant d'attribuer. Un enfant a la même
/// forme que la racine (`OccuredAt` + `Metadata`) — le lire à plat compte
/// son temps deux fois (57,3 s au lieu de 51,7 s sur la session de
/// référence).
///
/// Ce sont des **minorants** : Profiler n'écrit une racine qu'à partir de
/// 5 ms et un enfant qu'à partir de 0,1 ms. L'écran dira « au-dessus du
/// seuil de Profiler », jamais « tout le temps du mod ».
public struct ProfilerCosts: Equatable, Sendable {

    /// Découpage par les jalons `INFO` de Profiler (`[t ms][Fast|Slow] …`),
    /// sur la même horloge que `OccuredAt`.
    public enum Phase: String, CaseIterable, Sendable {
        /// Jusqu'au premier `LoadStageChanged` : lancement et écran titre.
        case launch
        /// Du premier `LoadStageChanged` à la fin (`Slow`) de `Day Started`.
        case load
        /// Après : la partie.
        case play
    }

    public struct Cost: Equatable, Sendable {
        public let modId: String
        public let eventType: String
        public let phase: Phase
        /// Temps propre cumulé, enfants retirés (ms).
        public let selfMs: Double
        public let calls: Int
        public let maxSelfMs: Double
    }

    /// Du plus coûteux au moins coûteux.
    public let costs: [Cost]
    /// Lignes `[RawLog]` lues, et celles dont le JSON n'a pas pu l'être.
    public let rawLogLines: Int
    public let unreadableLines: Int
    /// Sans jalon de chargement, tout est compté au lancement.
    public let hasLoadMarkers: Bool

    public var isEmpty: Bool { costs.isEmpty }

    /// Le temps propre par mod pour une phase, du plus coûteux au moins.
    public func byMod(_ phase: Phase) -> [(modId: String, selfMs: Double)] {
        var totals: [String: Double] = [:]
        for cost in costs where cost.phase == phase { totals[cost.modId, default: 0] += cost.selfMs }
        return totals.map { (modId: $0.key, selfMs: $0.value) }
            .sorted { ($0.selfMs, $1.modId) > ($1.selfMs, $0.modId) }
    }

    public func total(_ phase: Phase) -> Double {
        costs.filter { $0.phase == phase }.reduce(0) { $0 + $1.selfMs }
    }

    // MARK: - Lecture

    public init(log text: String) {
        var entries: [Entry] = []
        var raw = 0, unreadable = 0
        var loadStart: Double?, loadEnd: Double?
        let decoder = JSONDecoder()
        // `isNewline` : un journal en CRLF se découpe pareil.
        for line in text.split(whereSeparator: \.isNewline) {
            guard let close = line.firstIndex(of: "]"), line.first == "[" else { continue }
            let header = line[line.startIndex..<close]
            guard header.hasSuffix(" Profiler") else { continue }
            let message = line[line.index(after: close)...].drop { $0 == " " }
            if header.contains(" TRACE "), message.hasPrefix("[RawLog] ") {
                raw += 1
                let json = message.dropFirst("[RawLog] ".count)
                do { entries.append(try decoder.decode(Entry.self, from: Data(json.utf8))) }
                catch { unreadable += 1 } // compté : un format qui change se voit
            } else if header.contains(" INFO "), let marker = Self.marker(message) {
                if marker.name.hasPrefix("LoadStageChanged"), marker.fast, loadStart == nil {
                    loadStart = marker.at
                } else if marker.name == "Day Started", !marker.fast, loadEnd == nil {
                    loadEnd = marker.at
                }
            }
        }

        var buckets: [Key: (own: Double, calls: Int, max: Double)] = [:]
        func walk(_ entry: Entry, _ phase: Phase) {
            let meta = entry.metadata
            let children = meta.innerDetails ?? []
            if let duration = meta.duration {
                let own = max(0, duration - children.reduce(0) { $0 + ($1.metadata.duration ?? 0) })
                let key = Key(modId: meta.modId, eventType: meta.eventType, phase: phase)
                let previous = buckets[key] ?? (0, 0, 0)
                buckets[key] = (previous.own + own, previous.calls + 1, max(previous.max, own))
            }
            for child in children { walk(child, phase) }
        }
        for entry in entries {
            let phase: Phase
            if let start = loadStart, entry.occuredAt >= start {
                phase = (loadEnd.map { entry.occuredAt <= $0 } ?? true) ? .load : .play
            } else {
                phase = .launch
            }
            walk(entry, phase)
        }

        costs = buckets.map {
            Cost(modId: $0.key.modId, eventType: $0.key.eventType, phase: $0.key.phase,
                 selfMs: $0.value.own, calls: $0.value.calls, maxSelfMs: $0.value.max)
        }.sorted { ($0.selfMs, $1.modId, $1.eventType) > ($1.selfMs, $0.modId, $0.eventType) }
        rawLogLines = raw
        unreadableLines = unreadable
        hasLoadMarkers = loadStart != nil
    }

    /// `[4,606.15][Fast] Game Launched` → (4606.15, true, "Game Launched").
    /// Le nombre suit la culture du journal : séparateurs de milliers
    /// (virgule, espaces) retirés, virgule décimale acceptée.
    static func marker(_ message: Substring) -> (at: Double, fast: Bool, name: String)? {
        guard message.first == "[", let close = message.firstIndex(of: "]") else { return nil }
        var number = message[message.index(after: message.startIndex)..<close]
            .filter { !$0.isWhitespace }
        if number.contains("."), number.contains(",") { number.removeAll { $0 == "," } }
        guard let at = Double(number.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let rest = message[message.index(after: close)...]
        let fast: Bool
        if rest.hasPrefix("[Fast] ") { fast = true } else if rest.hasPrefix("[Slow] ") { fast = false } else { return nil }
        return (at, fast, String(rest.dropFirst("[Fast] ".count)))
    }

    private struct Key: Hashable {
        let modId: String, eventType: String, phase: Phase
    }

    private struct Entry: Decodable {
        let occuredAt: Double
        let metadata: Metadata
        enum CodingKeys: String, CodingKey { case occuredAt = "OccuredAt", metadata = "Metadata" }
    }

    private struct Metadata: Decodable {
        let duration: Double?
        let modId: String
        let eventType: String
        let innerDetails: [Entry]?
        enum CodingKeys: String, CodingKey {
            case duration = "Duration", modId = "ModId", eventType = "EventType", innerDetails = "InnerDetails"
        }
    }
}

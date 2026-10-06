import Foundation

/// D5-C — les cinq axes de l'étoile.
public enum ModImpactAxis: String, CaseIterable, Sendable { case fps, spikes, launch, save, alloc }

public enum ModImpactClass: String, Sendable { case low, medium, high }

/// La statistique d'une version d'un mod : médiane par axe sur ses sources.
public struct ModImpactVersionStats: Equatable, Sendable {
    public let version: String?
    public var measuredSources: [ModImpactAxis: Int] = [:]
    public var measuredLast: [ModImpactAxis: Date] = [:]
    /// Médianes des parts ; une clé absente = axe non mesuré (≠ 0).
    public let shares: [ModImpactAxis: Double]
    public let ranges: [ModImpactAxis: ClosedRange<Double>]
    public let sourceCount: Int
    public let inGameSources: Int
    public let launchSources: Int
    public let saveSources: Int
    public let patchedSources: Int
    public let first: Date
    public let last: Date
    public let msPerFrame: Double?
    public let frameWorkShare: Double?
    public let launchMs: Double?
    public let saveMs: Double?
    public let allocMBPerMinute: Double?

    public var score: Double { ModImpact.score(shares) }
    public var isNegligible: Bool {
        shares.allSatisfy { axis, value in
            value < (axis == .spikes ? ModImpactSample.spikeFloor : ModImpactSample.shareFloor)
        }
    }
    public var impactClass: ModImpactClass? { isNegligible ? nil : ModImpact.impactClass(score: score) }
}

/// Un mod installé et son historique ; `id` = `folderName` de l'entrée.
public struct ModImpactEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let modId: String
    public let name: String
    public let installedVersion: String
    public let isEnabled: Bool
    /// La plus récente (dernière mesure) d'abord.
    public let versions: [ModImpactVersionStats]

    /// Mesuré et négligeable — distinct de « jamais mesuré » (`shown == nil`).
    public var isNegligible: Bool { shown?.isNegligible ?? false }
    /// Versions connues ; « version inconnue » (segment sans inventaire) ne se
    /// compare à rien.
    public var comparableVersionCount: Int { versions.filter { $0.version != nil }.count }

    /// Le manifeste (« 7.4 ») et l'inventaire de la sonde (« 7.4.0 ») ne
    /// s'écrivent pas pareil : comparaison sémantique.
    public var current: ModImpactVersionStats? {
        versions.first { ModImpact.sameVersion($0.version, installedVersion) }
    }
    /// La version installée si mesurée, sinon la dernière version **connue**,
    /// et seulement à défaut « version inconnue ».
    public var shown: ModImpactVersionStats? {
        current ?? versions.first { $0.version != nil } ?? versions.first
    }

    /// La version connue mesurée juste avant l'installée.
    public var previousVersion: ModImpactVersionStats? {
        guard let current, let index = versions.firstIndex(of: current) else { return nil }
        return versions[(index + 1)...].first { $0.version != nil }
    }

    /// Note de la version installée moins celle de la précédente mesurée ;
    /// négatif = gain. Nil sans `minimumSourcesForEvolution` des deux côtés.
    public var evolution: Double? {
        guard let current, let previous = previousVersion,
              current.sourceCount >= ModImpact.minimumSourcesForEvolution,
              previous.sourceCount >= ModImpact.minimumSourcesForEvolution else { return nil }
        return current.score - previous.score
    }
}

public enum ModImpact {
    public static let weights: [ModImpactAxis: Double] = [.fps: 35, .spikes: 20, .launch: 15, .save: 15, .alloc: 15]
    public static let highThreshold = 15.0
    public static let mediumThreshold = 5.0
    public static let minimumSourcesForEvolution = 3

    /// Σ poids × √part sur les axes mesurés ; un axe absent compte 0, sans
    /// renormaliser (spec §3.3 : un pack à 2 % du lancement montait à 14).
    public static func score(_ shares: [ModImpactAxis: Double]) -> Double {
        shares.reduce(0) { $0 + (weights[$1.key] ?? 0) * $1.value.squareRoot() }
    }

    public static func impactClass(score: Double) -> ModImpactClass {
        score >= highThreshold ? .high : score >= mediumThreshold ? .medium : .low
    }

    /// Même version au sens SemVer : numéros complétés par des zéros
    /// (« 7.4 » = « 7.4.0 »), suffixes égaux sans casse.
    public static func sameVersion(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        func split(_ v: String) -> ([Int], String) {
            let parts = v.trimmingCharacters(in: .whitespaces).split(separator: "-", maxSplits: 1).map(String.init)
            return ((parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 },
                    parts.count > 1 ? parts[1].lowercased() : "")
        }
        let (x, sx) = split(a), (y, sy) = split(b)
        guard sx == sy else { return false }
        for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) { return false }
        return true
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Une statistique par version (nil = « version inconnue »), la plus
    /// récemment mesurée d'abord.
    public static func versionStats(_ samples: [ModImpactSample]) -> [ModImpactVersionStats] {
        let byVersion = Dictionary(grouping: samples, by: \.version)
        return byVersion.compactMap { version, list -> ModImpactVersionStats? in
            guard let first = list.map(\.date).min(), let last = list.map(\.date).max() else { return nil }
            let inGame = list.filter { $0.kind == .inGame }
            let launches = list.filter { $0.kind == .launch }
            let saves = list.filter { $0.kind == .save }
            let columns: [ModImpactAxis: [Double]] = [
                .fps: inGame.compactMap(\.fpsShare), .spikes: inGame.compactMap(\.spikeShare),
                .alloc: inGame.compactMap(\.allocShare),
                .launch: launches.compactMap(\.loadShare), .save: saves.compactMap(\.loadShare),
            ]
            var shares: [ModImpactAxis: Double] = [:], ranges: [ModImpactAxis: ClosedRange<Double>] = [:]
            for (axis, values) in columns {
                guard let m = median(values), let lo = values.min(), let hi = values.max() else { continue }
                shares[axis] = m
                ranges[axis] = lo...hi
            }
            var stats = ModImpactVersionStats(
                version: version, shares: shares, ranges: ranges,
                sourceCount: Set(list.map(\.sourceId)).count, inGameSources: inGame.count,
                launchSources: launches.count, saveSources: saves.count,
                patchedSources: inGame.filter { $0.patchesMeasured == true }.count,
                first: first, last: last,
                msPerFrame: median(inGame.compactMap(\.msPerFrame)),
                frameWorkShare: median(inGame.compactMap(\.frameWorkShare)),
                launchMs: median(launches.compactMap(\.ms)), saveMs: median(saves.compactMap(\.ms)),
                allocMBPerMinute: median(inGame.compactMap(\.allocMBPerMinute)))
            let measured: [ModImpactAxis: [ModImpactSample]] = [
                .fps: inGame.filter { $0.msPerFrame.map { $0.isFinite && $0 >= 0 } == true },
                .spikes: inGame.filter { $0.spikeShare.map { $0.isFinite && $0 >= 0 } == true },
                .alloc: inGame.filter { $0.allocMBPerMinute.map { $0.isFinite && $0 >= 0 } == true },
                .launch: launches.filter { $0.ms.map { $0.isFinite && $0 >= 0 } == true },
                .save: saves.filter { $0.ms.map { $0.isFinite && $0 >= 0 } == true }
            ]
            stats.measuredSources = measured.mapValues { Set($0.map(\.sourceId)).count }
            stats.measuredLast = measured.compactMapValues { $0.map(\.date).max() }
            return stats
        }
        .sorted { $0.last > $1.last }
    }

    /// Une entrée par mod installé (composants de pack compris), sonde exclue,
    /// rapprochée de l'historique par `UniqueID` sans casse.
    public static func entries(history: ModImpactHistory, mods: [ModItem]) -> [ModImpactEntry] {
        mods.flatMap { $0.isGroup ? ($0.children ?? []) : [$0] }
            .filter { !$0.uniqueId.isEmpty && !ModImpactSources.isProbe($0.uniqueId) }
            .map { item in
                ModImpactEntry(id: item.folderName, modId: item.uniqueId, name: item.name,
                               installedVersion: item.version, isEnabled: item.isEnabled,
                               versions: versionStats(history.samples[item.uniqueId.lowercased()] ?? []))
            }
    }

    /// Actifs, mesurés, non négligeables, par note décroissante (départage :
    /// identifiant).
    public static func ranking(_ entries: [ModImpactEntry]) -> [ModImpactEntry] {
        entries.filter { $0.isEnabled && $0.shown.map { !$0.isNegligible } == true }
            .sorted {
                let a = $0.shown?.score ?? 0, b = $1.shown?.score ?? 0
                return a != b ? a > b : $0.modId < $1.modId
            }
    }
}

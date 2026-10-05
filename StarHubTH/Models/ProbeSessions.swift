import Foundation

/// Une ligne de `timings.jsonl` : une minute réelle de jeu mesurée par la
/// sonde. Les champs apparus au fil des versions de la sonde sont optionnels
/// (les lignes de la v0.2 n'ont pas `InactiveTicks`).
public struct ProbeMinute: Decodable, Equatable, Sendable {
    public struct Stats: Decodable, Equatable, Sendable {
        public let count: Int
        public let avg: Double
        public let p50: Double
        public let p99: Double
        public let max: Double
    }

    public let session: String
    public let at: String
    public let wallSeconds: Double
    public let fps: Double
    public let location: String?
    public let menu: String?
    public let inactiveTicks: Int?
    public let frameInterval: Stats
    public let heapMB: Double?
    /// D4-T8 — mémoire **physique** courante du processus (sonde ≥ 0.9.11) :
    /// textures, MonoGame et bibliothèques natives, que le tas seul ignore —
    /// c'est ce qui gonfle un parc lourd.
    public let workingSetMB: Double?
    /// Le pic physique depuis le lancement du jeu — monotone : sert de
    /// libellé, pas de courbe.
    public let peakWorkingSetMB: Double?
    /// Mémoire réservée par .NET (`TotalCommittedBytes`) : le plafond que le
    /// ramasse-miettes s'est fixé, au-dessus du tas utilisé.
    public let committedMB: Double?
    /// D4-T6a — textures résidentes au total, sonde ≥ 0.9.13 opt-in
    /// `MeasureTextures`. RAM gérée, pas VRAM ; les textures créées en code
    /// ne passent pas par le ContentManager et sont invisibles.
    public let textureMB: Int64?
    public let textureCount: Int?
    /// Les octets retenus par attributaire (`vanilla` compris) — attribution
    /// partielle : loader de mod, sinon éditeur, sinon vanilla.
    public let textureByMod: [String: Int64]?
    public let loadedMods: Int?
    /// Ticks de la minute avec un menu ouvert (sonde ≥ 0.4.12).
    public let menuTicks: Int?
    /// Heure du jeu en fin de minute (`Game1.timeOfDay`), sonde ≥ 0.4.12.
    public let gameTime: Int?
    public let tick: Stats?
    public let update: Stats?
    public let draw: Stats?

    /// Part de la minute passée un menu ouvert. `nil` pour les lignes des
    /// sondes < 0.4.12 (champ absent) ou sans tick.
    public var menuShare: Double? {
        guard let menuTicks, let count = tick?.count, count > 0 else { return nil }
        return Double(menuTicks) / Double(count)
    }

    /// Fenêtre sans focus : MonoGame dort 20 ms par tick, la minute ne décrit
    /// pas le jeu.
    public var isUnfocused: Bool { (inactiveTicks ?? 0) > 0 }

    /// Écran titre ou chargement (aucun lieu). Pas « la première minute » :
    /// un retour au titre en milieu de session existe (4 cas réels).
    public var isAtTitle: Bool { location == nil }
}

/// Une ligne de `mod-costs.jsonl` : le coût de chaque mod pendant une minute.
public struct ProbeModCostMinute: Decodable, Equatable, Sendable {
    public struct EventCost: Decodable, Equatable, Sendable {
        public let event: String
        public let selfMs: Double
        public let maxMs: Double
        public let allocKB: Double
        public let calls: Int
    }

    public struct ModCost: Decodable, Equatable, Sendable {
        public let mod: String
        /// Temps propre total, **patches compris** (`FrameTimings.cs:226`).
        public let selfMs: Double
        /// Absent avant la v0.4.1 de la sonde.
        public let patchMs: Double?
        public let msPerSecond: Double
        public let maxMs: Double
        public let allocKB: Double
        public let calls: Int
        public let events: [EventCost]

        /// Le temps des gestionnaires d'événements seuls.
        public var eventOnlyMs: Double { selfMs - (patchMs ?? 0) }
    }

    public let session: String
    public let at: String
    public let wallSeconds: Double
    public let frames: Int
    public let inactiveTicks: Int?
    public let location: String?
    public let frameWorkMs: Double?
    public let eventMs: Double?
    public let patchMs: Double?
    public let patchesMeasured: Bool?
    public let interrupted: Bool?
    public let interruptReason: String?
    public let mods: [ModCost]
}

/// Une session de jeu de la sonde, identifiée par l'horodatage de son
/// démarrage (champ `Session` des deux fichiers).
public struct ProbeSession: Equatable, Sendable {
    public let id: String
    public let minutes: [ProbeMinute]
    public let costs: [ProbeModCostMinute]

    public var startedAt: Date? { ProbeDate.parse(id) }
}

public struct ProbeSessions: Equatable, Sendable {
    /// Du plus ancien au plus récent.
    public let sessions: [ProbeSession]
    /// Lignes illisibles des deux fichiers, comptées ensemble.
    public let unreadableLines: Int

    public static func group(minutes: [ProbeMinute], costs: [ProbeModCostMinute],
                             unreadableLines: Int = 0) -> ProbeSessions {
        var order: [String] = []
        var byMinutes: [String: [ProbeMinute]] = [:]
        var byCosts: [String: [ProbeModCostMinute]] = [:]
        for minute in minutes {
            if byMinutes[minute.session] == nil && byCosts[minute.session] == nil { order.append(minute.session) }
            byMinutes[minute.session, default: []].append(minute)
        }
        for cost in costs {
            if byMinutes[cost.session] == nil && byCosts[cost.session] == nil { order.append(cost.session) }
            byCosts[cost.session, default: []].append(cost)
        }
        let sessions = order
            .map { ProbeSession(id: $0, minutes: byMinutes[$0] ?? [], costs: byCosts[$0] ?? []) }
            .sorted { lhs, rhs in
                let l = lhs.startedAt ?? .distantPast, r = rhs.startedAt ?? .distantPast
                return l == r ? lhs.id < rhs.id : l < r
            }
        return ProbeSessions(sessions: sessions, unreadableLines: unreadableLines)
    }

    /// Fichier absent (`nil`) : aucune ligne de ce côté.
    public static func decode(timings: Data?, costs: Data?) -> ProbeSessions {
        let minutes = timings.map { ProbeJSON.lines(ProbeMinute.self, from: $0) } ?? (records: [], unreadable: 0)
        let costLines = costs.map { ProbeJSON.lines(ProbeModCostMinute.self, from: $0) } ?? (records: [], unreadable: 0)
        return group(minutes: minutes.records, costs: costLines.records,
                     unreadableLines: minutes.unreadable + costLines.unreadable)
    }
}

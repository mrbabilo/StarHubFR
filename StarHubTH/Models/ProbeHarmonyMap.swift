import Foundation

/// `harmony-map.json` de la sonde : chaque méthode patchée et ses
/// propriétaires, relevés dans Harmony pendant le jeu. La décompilation dit ce
/// qu'un mod **peut** patcher ; la carte dit ce qu'il **a** patché avec la
/// config du parc (A5-T7, marche 2).
///
/// Un propriétaire Harmony n'est pas toujours un UniqueID (16 sur 108 sur le
/// parc réel : `Cropgenics.cjb-compat`…) : il est rattaché au plus long
/// identifiant chargé qui le préfixe, suivi d'un point. La sonde elle-même
/// n'est jamais un propriétaire.
public struct ProbeHarmonyMap: Equatable, Sendable {
    public struct Mod: Decodable, Equatable, Sendable {
        public let uniqueID: String
        public let name: String
        /// Normalisée par SMAPI (`1.3.0` pour un manifeste `1.3`).
        public let version: String
    }

    public struct Patch: Decodable, Equatable, Sendable {
        public let kind: String
        public let owner: String
        public let ownerName: String?
        public let priority: Int
        public let patch: String
    }

    public struct Method: Equatable, Sendable {
        public let method: String
        public let declaringAssembly: String
        public let patches: [Patch]
        /// UniqueID des mods propriétaires, en minuscules.
        public let ownerMods: Set<String>
    }

    private struct RawMethod: Decodable {
        let method: String
        let declaringAssembly: String
        let patches: [Patch]
    }

    private struct RawMap: Decodable {
        let stage: String
        let capturedAt: String
        let mods: [Mod]
        let methods: [RawMethod]
    }

    private static let probeId = "mrbabilo.starhubfr.probe"

    public let stage: String
    public let capturedAt: String
    public let mods: [Mod]
    public let methods: [Method]
    /// Minuscules → mod chargé.
    private let modsById: [String: Mod]
    /// Propriétaire tel qu'écrit → UniqueID à la casse du manifeste, ou `nil`.
    private let ownerIndex: [String: String?]

    public static func decode(_ data: Data) -> ProbeHarmonyMap? {
        do {
            return ProbeHarmonyMap(raw: try ProbeJSON.decoder().decode(RawMap.self, from: data))
        } catch {
            return nil
        }
    }

    private init(raw: RawMap) {
        stage = raw.stage
        capturedAt = raw.capturedAt
        mods = raw.mods
        var byId: [String: Mod] = [:]
        for mod in raw.mods { byId[mod.uniqueID.lowercased()] = mod }
        modsById = byId
        let byLength = raw.mods.map(\.uniqueID).sorted { $0.count > $1.count }
        var index: [String: String?] = [:]
        for method in raw.methods {
            for patch in method.patches where index[patch.owner] == nil {
                index[patch.owner] = Self.resolve(patch.owner, byId: byId, byLength: byLength)
            }
        }
        ownerIndex = index
        methods = raw.methods.map { method in
            let owners = Set(method.patches.compactMap { index[$0.owner] ?? nil }.map { $0.lowercased() })
            return Method(method: method.method, declaringAssembly: method.declaringAssembly,
                          patches: method.patches, ownerMods: owners)
        }
    }

    private static func resolve(_ owner: String, byId: [String: Mod], byLength: [String]) -> String? {
        let lowered = owner.lowercased()
        let resolved = byId[lowered]?.uniqueID
            ?? byLength.first { lowered.hasPrefix($0.lowercased() + ".") }
        guard let resolved, resolved.lowercased() != probeId else { return nil }
        return resolved
    }

    public func isLoaded(_ uniqueId: String) -> Bool { modsById[uniqueId.lowercased()] != nil }

    public func version(of uniqueId: String) -> String? { modsById[uniqueId.lowercased()]?.version }

    public func modId(forOwner owner: String) -> String? {
        if let known = ownerIndex[owner] { return known }
        return Self.resolve(owner, byId: modsById, byLength: mods.map(\.uniqueID).sorted { $0.count > $1.count })
    }

    /// Méthodes patchées par les deux mods, au format du catalogue
    /// (`Type.méthode`, surcharges confondues), triées.
    public func sharedMethods(_ a: String, _ b: String) -> [String] {
        let a = a.lowercased(), b = b.lowercased()
        return Self.shortNames(methods.filter { $0.ownerMods.contains(a) && $0.ownerMods.contains(b) })
    }

    /// Méthodes déclarées dans l'assembly d'un autre mod et patchées par
    /// `uniqueId` : il modifie le code de l'autre.
    public func methods(patchedBy uniqueId: String, inAssembly assembly: String) -> [String] {
        let id = uniqueId.lowercased()
        return Self.shortNames(methods.filter { $0.declaringAssembly == assembly && $0.ownerMods.contains(id) })
    }

    private static func shortNames(_ methods: [Method]) -> [String] {
        Array(Set(methods.map { shortName($0.method) })).sorted()
    }

    /// `StardewValley.TerrainFeatures.Bush.draw(SpriteBatch)` → `Bush.draw` ;
    /// un constructeur garde son type : `LoadGameMenu+SaveFileSlot..ctor`.
    public static func shortName(_ method: String) -> String {
        let signature = method.split(separator: "(", maxSplits: 1).first.map(String.init) ?? method
        if let range = signature.range(of: "..") {
            let type = signature[..<range.lowerBound].split(separator: ".").last.map(String.init) ?? ""
            return type + ".." + signature[range.upperBound...]
        }
        return signature.split(separator: ".").suffix(2).joined(separator: ".")
    }
}

import Foundation

/// D2-T1 — la ligne `[OPTIMIZER CONFIG]` que **Stardew Loading Optimizer**
/// (SLO, `neoiw.StardewLoadingOptimizer`) journalise en `INFO` au démarrage :
/// un état de config **résolu** — profil, limites de cache, et pour chaque
/// optimisation le triplet *configuré/effectif/raison*
/// (`fastWarp=configured=True,effective=True,reason=single-player-session`).
/// Format relevé dans la DLL 1.0.0 (`ModEntry.cs`, décompilé le 2026-10-06).
///
/// Tolérant par construction : clés inconnues vont dans `raw`, clés connues
/// absentes restent `nil`, et une ligne qui a changé de forme rend `nil` —
/// jamais une valeur inventée.
public struct SloOptimizerConfig: Equatable, Sendable {
    /// Le triplet d'une optimisation : ce qui était demandé, ce que la
    /// session applique vraiment, et pourquoi ça diffère.
    public struct Optimization: Equatable, Sendable {
        public let configured: Bool?
        public let effective: Bool?
        public let reason: String?
    }

    /// Version du profil d'optimisation (`profile=`).
    public let profile: Int?
    /// Profil de ressources (`resourceProfile=`, ex. `low-memory-device`).
    public let resourceProfile: String?
    /// Les optimisations en triplet, par nom (les groupes connus du format
    /// 1.0.0 : `backgroundMapPreparation`, `backgroundImagePreparation`,
    /// `fastWarp`, `deferredTileSheets` — une version future qui en ajoute
    /// est reprise ici sans changement de code).
    public let optimizations: [String: Optimization]
    /// Toutes les paires simples `clé=valeur` de la ligne, texte brut — les
    /// limites de cache (`imageCacheLimit=512 MB`) y vivent en clair.
    public let raw: [String: String]

    /// La ligne du journal : préfixe SMAPI, puis `[OPTIMIZER CONFIG]`, puis
    /// les paires séparées par `", "`. Rend `nil` si le marqueur manque ou si
    /// plus rien ne se découpe en paires (forme changée).
    public static func parse(log: String) -> SloOptimizerConfig? {
        for line in log.split(whereSeparator: \.isNewline) {
            if let config = parse(line: String(line)) { return config }
        }
        return nil
    }

    public static func parse(line: String) -> SloOptimizerConfig? {
        // `[OPTIMIZER CONFIG MIGRATION]` porte le même préfixe : exiger le
        // crochet fermé immédiat, sinon la migration passerait pour la config.
        guard let marker = line.range(of: "[OPTIMIZER CONFIG] ") else { return nil }
        var body = String(line[marker.upperBound...])
        // La ligne se termine par un point, vestige de phrase C#.
        if body.hasSuffix(".") { body.removeLast() }
        guard !body.isEmpty else { return nil }

        var optimizations: [String: Optimization] = [:]
        var raw: [String: String] = [:]
        var pairs = 0
        for token in body.components(separatedBy: ", ") {
            guard let equals = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<equals])
            let value = String(token[token.index(after: equals)...])
            guard !key.isEmpty else { continue }
            pairs += 1
            if value.hasPrefix("configured=") {
                optimizations[key] = optimization(from: value)
            } else {
                raw[key] = value
            }
        }
        // Aucune paire lisible : la forme a changé, on rend la main.
        guard pairs > 0 else { return nil }
        return SloOptimizerConfig(profile: int(raw["profile"]),
                                  resourceProfile: raw["resourceProfile"],
                                  optimizations: optimizations,
                                  raw: raw)
    }

    /// `configured=True,effective=False,reason=some-reason` — les booléens du
    /// triplet arrivent capitalisés (config) ou minuscules (littéraux C#).
    private static func optimization(from text: String) -> Optimization {
        var configured: Bool?
        var effective: Bool?
        var reason: String?
        for part in text.components(separatedBy: ",") {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = String(part[..<equals])
            let value = String(part[part.index(after: equals)...])
            switch key {
            case "configured": configured = bool(value)
            case "effective": effective = bool(value)
            case "reason": reason = value
            default: break
            }
        }
        return Optimization(configured: configured, effective: effective, reason: reason)
    }

    static func bool(_ text: String?) -> Bool? {
        text.map { $0.lowercased() == "true" }
    }

    static func int(_ text: String?) -> Int? {
        text.flatMap(Int.init)
    }

    /// Les nombres du journal peuvent porter une virgule décimale (le
    /// process du jeu suit la locale : `0,8x` sur un système en français).
    static func double(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

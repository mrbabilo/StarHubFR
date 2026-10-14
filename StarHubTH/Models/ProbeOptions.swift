import Foundation

/// D4-T6 bis — les options de configuration de la sonde StarHubFR, lues et
/// réécrites par l'app : la fiche sonde les expose en Toggles, et l'écriture
/// est **toujours propre**. La config éditée à la main du 2026-10-05 portait
/// une virgule manquante que SMAPI rejetait en silence — défauts, mesure
/// jamais armée, une session de débogage pour un caractère.
///
/// La lecture tolère l'absence des champs (défauts), pas la corruption : un
/// fichier illisible échoue et le **dit** — jamais un faux « option
/// désactivée ». La réécriture part d'un ordre canonique (tri alphabétique),
/// préserve tout champ inconnu du fichier d'origine, et rend du JSON valable
/// même quand elle répare.
public struct ProbeOptions: Equatable, Sendable {
    public let measureHarmonyPatches: Bool
    public let measureTextures: Bool
    /// Les mini-stats en jeu (FPS, P50/P99 des trames, mémoire), coin haut
    /// droit — `MiniStats.cs`, sonde 0.9.25+.
    public let showMiniStats: Bool

    /// Les défauts du `config.json` créé au premier lancement de la sonde
    /// (`ModConfig.cs`).
    public static let defaultHarmonyPatches = false
    public static let defaultTextures = false
    public static let defaultMiniStats = false

    public enum ReadFailure: Error, Equatable, Sendable {
        /// Présent mais pas un objet JSON valable : le geste « réparer »
        /// réécrit depuis les défauts.
        case unreadable
    }

    public init(measureHarmonyPatches: Bool = ProbeOptions.defaultHarmonyPatches,
                measureTextures: Bool = ProbeOptions.defaultTextures,
                showMiniStats: Bool = ProbeOptions.defaultMiniStats) {
        self.measureHarmonyPatches = measureHarmonyPatches
        self.measureTextures = measureTextures
        self.showMiniStats = showMiniStats
    }

    public static func read(_ data: Data) -> Result<ProbeOptions, ReadFailure> {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.unreadable)
        }
        return .success(ProbeOptions(
            measureHarmonyPatches: object["MeasureHarmonyPatches"] as? Bool ?? defaultHarmonyPatches,
            measureTextures: object["MeasureTextures"] as? Bool ?? defaultTextures,
            showMiniStats: object["ShowMiniStats"] as? Bool ?? defaultMiniStats))
    }

    /// La réécriture : les options connues, puis tout champ inconnu du fichier
    /// d'origine (absent, corrompu : rien à préserver). `sortedKeys` rend
    /// l'ordre canonique — réécrire la même chose rend les mêmes octets.
    public static func rewritten(original: Data?, options: ProbeOptions) throws -> Data {
        var out: [String: Any] = [
            "MeasureHarmonyPatches": options.measureHarmonyPatches,
            "MeasureTextures": options.measureTextures,
            "ShowMiniStats": options.showMiniStats,
        ]
        if let original,
           let old = (try? JSONSerialization.jsonObject(with: original)) as? [String: Any] {
            for (key, value) in old where out[key] == nil { out[key] = value }
        }
        return try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }
}

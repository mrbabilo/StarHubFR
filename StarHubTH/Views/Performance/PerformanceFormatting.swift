import SwiftUI

/// Helpers partagés des écrans Performance — chaque corps de `name(...)`,
/// `number(...)` et `reasonName(...)` existait en deux ou trois copies
/// identiques dans les sections voisines (passe de simplification
/// 2026-10-03). Les sections gardent leurs mini-wrappers : les appels ne
/// bougent pas, la logique n'a plus qu'un domicile.
///
/// NB : `number` passe par `.formatted(.number...)`, qui suit la **locale
/// système** ; `ModImpactFormat.number` (Models), lui, suit la langue de
/// l'interface. Les deux cohabitent sur le même écran — écart connu, non
/// modifié ici.
enum PerformanceFormatting {
    /// Le nom du manifeste quand le mod est installé, sinon l'identifiant.
    static func modName(_ modId: String, viewModel: StarHubTHViewModel) -> String {
        viewModel.scanStore.mods.flattenedMods
            .first { $0.uniqueId.caseInsensitiveCompare(modId) == .orderedSame }?.name ?? modId
    }

    static func number(_ value: Double?, fraction: Int = 1) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(fraction))) } ?? "—"
    }

    /// Libellé localisé d'un motif d'exclusion de la sonde.
    static func reasonName(_ reason: ProbeExclusionReason, _ localization: LocalizationStore) -> String {
        switch reason {
        case .unfocused: return localization.L(L10n.Performance.reasonUnfocused)
        case .title: return localization.L(L10n.Performance.reasonTitle)
        case .menuOpen: return localization.L(L10n.Performance.reasonMenu)
        case .night: return localization.L(L10n.Performance.reasonNight)
        case .firstAfterTitle: return localization.L(L10n.Performance.reasonLoading)
        }
    }

    /// Libellé localisé d'un compteur de scène (D4-T9). Une clé ajoutée un
    /// jour par la sonde sans libellé ici est ignorée, pas affichée brute.
    static func sceneName(_ key: String, _ localization: LocalizationStore) -> String? {
        let keys: [String: String] = [
            "npcs": L10n.Performance.sceneNpcs,
            "animals": L10n.Performance.sceneAnimals,
            "furniture": L10n.Performance.sceneFurniture,
            "objects": L10n.Performance.sceneObjects,
            "terrainFeatures": L10n.Performance.sceneTerrain,
            "largeTerrainFeatures": L10n.Performance.sceneLargeTerrain,
            "resourceClumps": L10n.Performance.sceneResourceClumps,
            "lights": L10n.Performance.sceneLights,
            "temporarySprites": L10n.Performance.sceneTemporarySprites,
            "debris": L10n.Performance.sceneDebris,
            "locations": L10n.Performance.sceneLocations,
        ]
        return keys[key].map { localization.L($0) }
    }

    /// Note secondaire (pied de section, avertissement) — deux copies
    /// identiques (`ModImpactSection`, `PerformanceProbeSection`).
    static func note(_ text: String) -> some View {
        Text(text)
            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

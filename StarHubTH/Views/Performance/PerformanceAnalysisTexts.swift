import SwiftUI

/// Les textes et glyphes de la carte « Analyse et conclusion » : conclusion,
/// preuve (la confiance de `ProbeAnalysis`, distincte de la **qualité** d'une
/// métrique — deux calculs, deux vocabulaires depuis le lot C), lignes de
/// preuves. Sortis de `PerformanceAnalysisSection` (plafond 400 lignes).
enum PerformanceAnalysisTexts {
    static func conclusion(_ report: ProbePerformanceReport, _ localization: LocalizationStore) -> String {
        report.metrics[.frameP50].map { PerformanceMetricText.outcome($0.outcome, localization) }
            ?? localization.L(L10n.PerformanceEvidence.unavailable)
    }

    /// Le nom court d'un côté : le nom de la mesure guidée, sinon la date.
    static func sideTitle(_ side: ProbeSide) -> String {
        if let measurement = side.measurement { return measurement.name }
        guard let start = side.start else { return "—" }
        return start.formatted(date: .abbreviated, time: .shortened)
    }

    /// Même jeu d'icônes et de teintes que les tuiles, la Chronologie et les
    /// Chargements (lot B, P2).
    static func directionVisuals(_ direction: ProbeAnalysisResult.Direction) -> (icon: String, tint: Color) {
        switch direction {
        case .faster: return ("arrow.down.right", AppDesign.Color.success)
        case .slower: return ("arrow.up.right", AppDesign.Color.warning)
        case .noDifference: return ("equal", .secondary)
        case .inconclusive: return ("questionmark", .secondary)
        }
    }

    /// Pas de vert : il dit « mieux », pas « sûr ».
    static func confidenceVisuals(_ confidence: ProbeAnalysisResult.Confidence) -> (icon: String, tint: Color) {
        switch confidence {
        case .high: return ("checkmark.seal.fill", AppDesign.Color.accent)
        case .medium: return ("circle.lefthalf.filled", .secondary)
        case .low: return ("exclamationmark.circle", .secondary)
        }
    }

    static func confidence(_ confidence: ProbeAnalysisResult.Confidence, _ localization: LocalizationStore) -> String {
        switch confidence {
        case .high: return localization.L(L10n.Performance.confidenceHigh)
        case .medium: return localization.L(L10n.Performance.confidenceMedium)
        case .low: return localization.L(L10n.Performance.confidenceLow)
        }
    }

    static func evidence(_ evidence: ProbeAnalysisResult.Evidence, _ localization: LocalizationStore,
                         name: (String) -> String) -> String {
        switch evidence {
        case .comparableMinutes(let a, let b, let same):
            let suffix = same ? ", " + localization.L(L10n.Performance.sameLocations).lowercased() : ""
            return String(format: localization.L(L10n.Performance.evidenceMinutes), a, b, suffix)
        case .singleChange(let modId):
            return String(format: localization.L(L10n.Performance.evidenceSingleChange), name(modId))
        case .changeCount(let count):
            return String(format: localization.L(L10n.Performance.evidenceChangeCount), count)
        case .directCost(let modId, let delta):
            return String(format: localization.L(L10n.Performance.evidenceDirectCost), name(modId),
                          delta.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())))
        case .indirectShare(let share):
            return String(format: localization.L(L10n.Performance.evidenceIndirect), Int((share * 100).rounded()))
        case .probeChanged: return localization.L(L10n.Performance.evidenceProbe)
        case .envelopesAsymmetric: return localization.L(L10n.Performance.evidenceEnvelopes)
        case .cleanMeasurement: return localization.L(L10n.Performance.evidenceClean)
        case .excludedMinutes(let a, let b):
            return String(format: localization.L(L10n.Performance.evidenceExcluded),
                          counts(a, localization), counts(b, localization))
        case .frameWorkUnchanged: return localization.L(L10n.Performance.evidenceFrameWork)
        case .noisyMeasurement: return localization.L(L10n.Performance.evidenceNoisy)
        }
    }

    private static func counts(_ exclusions: [ProbeExclusionReason: Int], _ localization: LocalizationStore) -> String {
        exclusions.isEmpty ? "—" : exclusions.sorted { $0.value > $1.value }
            .map { "\(PerformanceFormatting.reasonName($0.key, localization)) ×\($0.value)" }.joined(separator: ", ")
    }
}

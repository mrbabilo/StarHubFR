import SwiftUI

/// Les conseils de la carte de santé, tirés des diagnostics — sortis du
/// fichier de la carte (plafond de taille) quand ses compteurs sont devenus
/// cliquables (2026-10-03).
extension SmapiHealthCard {
    // MARK: - Suggestions

    /// Actionable, plain-language advice derived from the diagnostics, ordered
    /// most-blocking first (missing dependencies and load failures before
    /// advisory notes). Formatting lives here, not in the pure parser.
    var suggestions: [String] {
        var out: [String] = []
        let d = diagnostics

        for dep in d.missingDeps {
            out.append(String(format: localization.L(L10n.Logs.healthSgMissingDep), dep.missing, dep.mod))
        }
        // Mods already covered by a missing-dependency tip don't need a second,
        // vaguer one repeating the same root cause.
        let depMods = Set(d.missingDeps.map(\.mod))
        for issue in d.skipped where !depMods.contains(issue.name) {
            out.append(advice(for: issue, fallback: L10n.Logs.healthSgSkipped))
        }
        for issue in d.failed where !depMods.contains(issue.name) {
            out.append(advice(for: issue, fallback: L10n.Logs.healthSgFailed))
        }
        if !d.brokenMods.isEmpty {
            out.append(localization.L(L10n.Logs.healthSgBroken))
        }
        if d.externalConflicts.contains(where: { $0.contains("RivaTuner") }) {
            out.append(localization.L(L10n.Logs.healthSgRivatuner))
        }
        for mod in d.saveSerializerMods {
            out.append(String(format: localization.L(L10n.Logs.healthSgSave), mod))
        }
        if let worst = d.topErrorMods.first, worst.count >= 5 {
            out.append(String(format: localization.L(L10n.Logs.healthSgErrorMod), worst.name, Int64(worst.count)))
        }
        if d.patchedMods.count >= 15 {
            out.append(String(format: localization.L(L10n.Logs.healthSgPatchedMany), Int64(d.patchedMods.count)))
        }
        // Keep the advice list readable: per-mod tips could otherwise run to
        // dozens of lines. Ordering above puts the most blocking ones first,
        // and the categories below still list every affected mod.
        if out.count > Self.maxSuggestions {
            let hidden = out.count - Self.maxSuggestions
            out = Array(out.prefix(Self.maxSuggestions))
            out.append(String(format: localization.L(L10n.Logs.healthAndMore), Int64(hidden)))
        }
        return out
    }

    /// Max suggestions shown before collapsing into "…and N more".
    static let maxSuggestions = 6

    /// Maps a load failure to the most specific fix we can offer. SMAPI's raw
    /// reasons are accurate but cryptic ("its DLL couldn't be loaded: … already
    /// loaded"), so recognized families get a concrete instruction; anything
    /// unrecognized falls back to quoting the reason verbatim.
    static let adviceRules: [(patterns: [String], key: String)] = [
        (["already loaded", "two copies", "duplicate"], L10n.Logs.healthSgDuplicate),
        (["requires a newer version", "older version of smapi", "needs smapi",
          "compatible with stardew valley", "requires stardew valley",
          "not compatible with this version"], L10n.Logs.healthSgGameVersion),
        (["manifest.json", "manifest is invalid", "invalid manifest",
          "no manifest", "couldn't parse manifest"], L10n.Logs.healthSgManifest),
        (["not in a folder", "wrong folder", "subfolder"], L10n.Logs.healthSgFolder)
    ]

    func advice(for issue: SmapiDiagnostics.Issue, fallback: String) -> String {
        let reason = issue.reason.lowercased()
        for rule in Self.adviceRules where rule.patterns.contains(where: reason.contains) {
            return String(format: localization.L(rule.key), issue.name)
        }
        return String(format: localization.L(fallback), issue.name, issue.reason)
    }
}

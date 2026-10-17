import Foundation

/// N-09 S9 (audit UX 2026-10-16) — un conseil de « Ce que vous pouvez
/// faire », avec le geste qui le suit. Avant, la liste n'était que de la
/// prose : « Installez X », et rien pour l'installer.
///
/// Sorti de `SmapiHealthCard+Suggestions` (vue, intestable) : l'ordre, les
/// seuils et les familles de pannes se testent ici. Le texte passe par la
/// fermeture de traduction ; le type ne connaît pas `LocalizationStore`.
public struct HealthSuggestion: Equatable, Sendable {

    public enum Action: Equatable, Sendable {
        /// La feuille des dépendances manquantes. `missing` est ce que SMAPI
        /// écrit entre parenthèses : un ou plusieurs `UniqueID`.
        case installDependency(missing: String)
        /// La fiche du mod, par le canal `.jumpToMod` (`ModFocusResolver`).
        case openMod(String)
        /// Défiler jusqu'à un bloc de la carte (son `id`).
        case showBlock(String)
        /// Défiler jusqu'à la recherche guidée — sans la lancer : elle met
        /// des mods en pause.
        case showBisection
    }

    public let text: String
    /// nil : un conseil sans cible dans l'app (RivaTuner, « … et N autres »).
    public let action: Action?

    public init(text: String, action: Action?) {
        self.text = text
        self.action = action
    }

    /// Conseils montrés avant de replier en « … et N autres ».
    public static let maxShown = 6

    /// Les conseils tirés du journal, les plus bloquants d'abord (dépendances
    /// manquantes et échecs de chargement avant les avertissements).
    public static func list(from d: SmapiDiagnostics,
                            localized localize: (String) -> String) -> [HealthSuggestion] {
        var out: [HealthSuggestion] = []

        for dep in d.missingDeps {
            out.append(.init(text: String(format: localize(L10n.Logs.healthSgMissingDep), dep.missing, dep.mod),
                             action: .installDependency(missing: dep.missing)))
        }
        // Un mod déjà couvert par un conseil de dépendance n'en reçoit pas un
        // second, plus vague, qui répéterait la même cause.
        let depMods = Set(d.missingDeps.map(\.mod))
        for issue in d.skipped where !depMods.contains(issue.name) {
            out.append(.init(text: advice(for: issue, fallback: L10n.Logs.healthSgSkipped, localized: localize),
                             action: .openMod(issue.name)))
        }
        for issue in d.failed where !depMods.contains(issue.name) {
            out.append(.init(text: advice(for: issue, fallback: L10n.Logs.healthSgFailed, localized: localize),
                             action: .openMod(issue.name)))
        }
        if !d.brokenMods.isEmpty {
            out.append(.init(text: localize(L10n.Logs.healthSgBroken), action: .showBlock("blocking")))
        }
        if d.externalConflicts.contains(where: { $0.contains("RivaTuner") }) {
            out.append(.init(text: localize(L10n.Logs.healthSgRivatuner), action: nil))
        }
        for mod in d.saveSerializerMods {
            out.append(.init(text: String(format: localize(L10n.Logs.healthSgSave), mod), action: .openMod(mod)))
        }
        if let worst = d.topErrorMods.first, worst.count >= 5 {
            out.append(.init(text: String(format: localize(L10n.Logs.healthSgErrorMod), worst.name, Int64(worst.count)),
                             action: .openMod(worst.name)))
        }
        if d.patchedMods.count >= 15 {
            out.append(.init(text: String(format: localize(L10n.Logs.healthSgPatchedMany), Int64(d.patchedMods.count)),
                             action: .showBisection))
        }
        // Une liste lisible : les conseils par mod iraient sinon à des
        // dizaines de lignes. Les blocs plus bas listent chaque mod touché.
        if out.count > maxShown {
            let hidden = out.count - maxShown
            out = Array(out.prefix(maxShown))
            out.append(.init(text: String(format: localize(L10n.Logs.healthAndMore), Int64(hidden)), action: nil))
        }
        return out
    }

    /// Les familles d'échec reconnues et leur consigne. Les raisons brutes de
    /// SMAPI sont exactes mais obscures (« its DLL couldn't be loaded: …
    /// already loaded ») ; une raison inconnue est citée telle quelle.
    static let adviceRules: [(patterns: [String], key: String)] = [
        (["already loaded", "two copies", "duplicate"], L10n.Logs.healthSgDuplicate),
        (["requires a newer version", "older version of smapi", "needs smapi",
          "compatible with stardew valley", "requires stardew valley",
          "not compatible with this version"], L10n.Logs.healthSgGameVersion),
        (["manifest.json", "manifest is invalid", "invalid manifest",
          "no manifest", "couldn't parse manifest"], L10n.Logs.healthSgManifest),
        (["not in a folder", "wrong folder", "subfolder"], L10n.Logs.healthSgFolder)
    ]

    static func advice(for issue: SmapiDiagnostics.Issue, fallback: String,
                       localized localize: (String) -> String) -> String {
        let reason = issue.reason.lowercased()
        for rule in adviceRules where rule.patterns.contains(where: reason.contains) {
            return String(format: localize(rule.key), issue.name)
        }
        return String(format: localize(fallback), issue.name, issue.reason)
    }

    /// Le journal peut dater : une dépendance qu'il dit absente peut avoir
    /// été installée depuis (ou le mod qui l'exige mis en pause). Vrai si
    /// l'un des `UniqueID` cités manque **encore** d'après le disque.
    public static func isStillMissing(_ missing: String, in plan: [MissingDependency]) -> Bool {
        let cited = Set(missing.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
        return plan.contains { $0.uniqueIds.contains { cited.contains($0.lowercased()) } }
    }
}

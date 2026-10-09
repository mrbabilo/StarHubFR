import Foundation

/// Une étape du guide de premier lancement, dans l'ordre canonique (huit
/// étapes). Type pur du Core : l'ordre et les clés de titre se testent sans
/// GUI ; `OnboardingView` (module app) itère sur `allCases` et lit
/// `titleKey` via `localization.L(_:)`.
public enum OnboardingStep: String, CaseIterable, Sendable {
    case welcome, gameDir, modsFolder, smapi, apiKey, localAI, extensions, done

    /// Clé brute dans `assets/{en,fr}.json` — ces huit clés vivent ici et
    /// n'ont **pas** de doublon dans `L10n.swift` : deux sources pour une
    /// même chaîne finiraient par diverger.
    public var titleKey: String {
        switch self {
        case .welcome: "onboarding_step_welcome"
        case .gameDir: "onboarding_step_game_dir"
        case .modsFolder: "onboarding_step_mods"
        case .smapi: "onboarding_step_smapi"
        case .apiKey: "onboarding_step_api_key"
        case .localAI: "onboarding_step_ai"
        case .extensions: "onboarding_step_extensions"
        case .done: "onboarding_step_done"
        }
    }

    /// L'étape suivante, `nil` sur la dernière.
    public var next: OnboardingStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

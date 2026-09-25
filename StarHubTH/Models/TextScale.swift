import Foundation

/// La taille du texte choisie dans Réglages › Affichage (I-T4) : trois
/// crans, appliqués aux polices en jetons (`AppDesign.Font`).
///
/// macOS n'offre pas de taille de texte système aux apps tierces : le
/// réglage vit dans l'app. Trois crans et non un curseur — la liste de
/// 1 000 mods doit rester lisible à chaque cran, et trois se vérifient.
public enum TextScale: String, CaseIterable, Sendable {
    case normal, large, extraLarge

    public static let defaultsKey = "textScale"

    public var factor: Double {
        switch self {
        case .normal: return 1
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }

    /// Le cran enregistré ; une valeur inconnue (réglage d'une version
    /// future, défaut abîmé) vaut « normal », jamais un plantage.
    public static func stored(in defaults: UserDefaults = .standard) -> TextScale {
        defaults.string(forKey: defaultsKey).flatMap(TextScale.init(rawValue:)) ?? .normal
    }
}

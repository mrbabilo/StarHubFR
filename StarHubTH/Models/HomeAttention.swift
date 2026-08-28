import Foundation

/// Ce que l'accueil doit dire en arrivant : **qu'est-ce qui demande mon
/// attention**, et **est-ce que je peux jouer**.
///
/// Les chiffres viennent tous d'états déjà exposés par le ViewModel — les
/// mêmes que ceux des badges de la barre latérale. Ce qui vit ici, c'est la
/// *résolution* : lequel mérite d'être teinté, et lequel n'est qu'un constat.
/// C'est aussi la seule part de l'accueil qu'un test peut atteindre.
public enum HomeAttention {

    /// Teinté ou neutre. Jamais « caché » : un zéro affiché est une
    /// information — il calibre les trois autres chiffres.
    public enum Level: Equatable {
        case calm
        case attention
    }

    public enum Kind: String, CaseIterable, Equatable {
        case updates
        case alerts
        case quarantine
        case library

        /// L'onglet où mène le compteur. Le porter ici évite que chaque vue
        /// refasse l'association — et que l'une d'elles se trompe.
        public var tab: String {
            switch self {
            case .updates: return "Updates"
            case .alerts: return "SystemAlerts"
            case .quarantine: return "Quarantine"
            case .library: return "Mods"
            }
        }
    }

    public struct Counter: Identifiable, Equatable {
        public let kind: Kind
        public let count: Int
        public let level: Level
        public var id: Kind { kind }
        public var tab: String { kind.tab }
    }

    /// Les quatre compteurs de la bande d'accueil, **toujours** les quatre.
    ///
    /// `mods` ne lève jamais l'attention : le parc est un constat. Un parc
    /// vide n'est pas une panne, et un gros parc encore moins.
    public static func counters(updates: Int, alerts: Int,
                                quarantined: Int, mods: Int) -> [Counter] {
        [
            Counter(kind: .updates, count: updates,
                    level: updates > 0 ? .attention : .calm),
            Counter(kind: .alerts, count: alerts,
                    level: alerts > 0 ? .attention : .calm),
            Counter(kind: .quarantine, count: quarantined,
                    level: quarantined > 0 ? .attention : .calm),
            Counter(kind: .library, count: mods, level: .calm),
        ]
    }
}

/// Le mode dans lequel le bouton de lancement partira.
public enum HomeLaunchMode: Equatable {
    case vanilla
    case smapi
}

/// Où en est la possibilité de jouer — et donc ce que la carte de lancement
/// doit proposer. Un bouton « Jouer » grisé et muet ne dit pas quoi faire :
/// chaque état empêché porte l'action qui le lève (spec refonte §2, P1).
public enum HomeLaunchState: Equatable {
    /// Aucun dossier de jeu : rien d'autre n'a de sens tant qu'il manque.
    case needsGameFolder
    /// Dossier connu, SMAPI absent, et le profil en demande.
    case needsSmapi
    // Note : `mode` est le mode **demandé** (la clé `launchProfile`), pas
    // forcément celui qui partira — `launchGame()` retombe sur SMAPI quand le
    // binaire vanilla n'existe pas. C'est l'affichage d'aujourd'hui.
    case ready(mode: HomeLaunchMode)

    public static func resolve(gameDirIsEmpty: Bool,
                               smapiInstalled: Bool,
                               profileIsVanilla: Bool) -> HomeLaunchState {
        // Le dossier prime : sans lui, installer SMAPI n'aurait nulle part où
        // écrire, et proposer l'installation serait une impasse.
        if gameDirIsEmpty { return .needsGameFolder }
        if profileIsVanilla { return .ready(mode: .vanilla) }
        return smapiInstalled ? .ready(mode: .smapi) : .needsSmapi
    }
}

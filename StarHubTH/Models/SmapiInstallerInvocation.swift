import Foundation

/// L'action demandée à l'installateur SMAPI — portée par son drapeau.
///
/// `Sendable` explicite : un type `public` n'a pas d'inférence, et la valeur
/// traverse les closures `@Sendable` du flux d'installation (P5-L4) — sans
/// la conformité, sa capture diagnostique.
public enum SmapiInstallerAction: String, Sendable {
    case install = "--install"
    case uninstall = "--uninstall"
}

/// Le contrat d'invocation de l'installateur SMAPI ≥ 4.x, par drapeaux
/// (X32).
///
/// Mesuré le 2026-09-06 sur le vrai binaire 4.5.2, lancé sur une installation
/// de contrôle (dossier factice contenant `Stardew Valley`,
/// `Stardew Valley.dll`, `.deps.json`, `.runtimeconfig.json`) :
///
/// - `--install --game-path P` : « Just one question first » — le jeu de
///   couleurs — puis « That's all I need! I'll install SMAPI now. »,
///   « SMAPI is installed! ». Le dossier `Mods/` est créé, les mods groupés
///   (Console Commands, Save Backup) posés.
/// - `--uninstall --game-path P` : « SMAPI is removed! » ; `smapi-internal/`
///   et `StardewModdingAPI*` partent, `Mods/` — les mods de l'utilisateur —
///   est conservé.
/// - `--install --uninstall` ensemble : refus immédiat et propre.
/// - dossier sans exécutable du jeu : la question couleurs est posée, puis
///   « That directory doesn't contain a Stardew Valley executable. »,
///   « Failed finding your game path. » — et **sortie**. L'ancien mode
///   interactif rebouclait sur la question à l'infini sur stdin fermé
///   (l'amorce de X30) ; le mode drapeaux ne fait plus jamais ça.
/// - le code de sortie vaut **0 même en échec** (le `ReadKey` final sur un
///   stdin non-terminal lève une exception .NET non gérée uniquement sur
///   certains chemins) : la réussite se juge sur le message et les preuves
///   disque, jamais sur l'exit code.
///
/// L'ancien pilotage écrivait quatre réponses d'un coup (`1`, `2`, le
/// chemin, l'action) dans un ordre supposé stable : une seule question
/// réordonnée ou retirée par une future version décalait toute la file — le
/// chemin devenait la réponse à une autre question. Les drapeaux verrouillent
/// le contrat ; la seule entrée restante est le jeu de couleurs.
public extension SmapiInstallerAction {

    /// Les libellés du chemin **partagé** entre installation et
    /// désinstallation — téléchargement, préparation, échec générique.
    ///
    /// Les deux actions passent par le même code : on télécharge la dernière
    /// archive de l'installateur, on l'extrait, on la rend exécutable, puis on
    /// la lance avec son drapeau. Le code étant partagé, les messages l'étaient
    /// aussi — et une désinstallation annonçait « Téléchargement de SMAPI… »,
    /// « Préparation de l'installation de SMAPI… », puis « Erreur
    /// d'installation » quand elle échouait. Trois mensonges dans le seul
    /// écran que l'utilisateur regarde pendant l'opération (relevé le
    /// 2026-09-14 après une désinstallation réelle).
    ///
    /// Ce qui reste commun est commun **pour de bon** : l'échec de
    /// téléchargement, l'extraction, la charge utile absente et l'interruption
    /// de l'installateur nomment ce qui a échoué, pas l'action demandée.
    var downloadingMessageKey: String {
        switch self {
        case .install: L10n.Smapi.downloading
        case .uninstall: L10n.Smapi.downloadingUninstall
        }
    }

    var preparingMessageKey: String {
        switch self {
        case .install: L10n.Smapi.preparing
        case .uninstall: L10n.Smapi.preparingUninstall
        }
    }

    /// L'échec qui ne sait rien dire de plus précis — une exception de copie,
    /// un `Process` qui refuse de démarrer. L'installateur, lui, rend déjà ses
    /// propres verdicts par action (`installError` / `uninstallFailed`).
    var genericFailureMessageKey: String {
        switch self {
        case .install: L10n.Smapi.installError
        case .uninstall: L10n.Smapi.uninstallFailed
        }
    }
}

public enum SmapiInstallerInvocation {

    /// La seule question que l'installateur pose encore sous drapeaux : le
    /// jeu de couleurs. « 1 » = texte sombre sur fond clair.
    public static let stdinAnswers = "1\n"

    /// Arguments de ligne de commande pour l'installateur. Le chemin passe
    /// **brut** : `Process.arguments` n'est pas un shell, il n'y a rien à
    /// citer — même avec l'espace de « Stardew Valley.app ».
    public static func arguments(action: SmapiInstallerAction, gamePath: String) -> [String] {
        [action.rawValue, "--game-path", gamePath]
    }
}

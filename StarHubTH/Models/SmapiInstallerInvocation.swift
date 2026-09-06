import Foundation

/// L'action demandée à l'installateur SMAPI — portée par son drapeau.
public enum SmapiInstallerAction: String {
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

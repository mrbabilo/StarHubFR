import Foundation

/// Ce qu'on accepte de lire d'un installateur SMAPI avant de le couper.
///
/// **Mesuré le 2026-09-04 sur `SMAPI 4.5.2`.** L'installateur officiel pose ses
/// questions sur l'entrée standard ; l'app y écrit ses quatre réponses puis
/// ferme le tube. Si une réponse ne lui convient pas — un chemin de jeu qu'il
/// refuse, une question de plus dans une version future — il repose la question,
/// lit une entrée close, et **boucle sans fin** :
///
/// ```
/// Type the file path to the game directory …, then press enter.
/// You must specify a directory path to continue.
/// ```
///
/// En 20 secondes, ce cycle a produit **119 827 838 octets** — près de 6 Mo par
/// seconde. `readDataToEndOfFile()` les accumule en mémoire : l'app grossissait
/// de ~360 Mo par minute, barre de progression figée à 80 %, sans autre issue
/// que de la tuer.
///
/// Un déroulement normal tient en quelques dizaines de lignes ; le plafond est
/// à 1 Mo, soit trois ordres de grandeur au-dessus, atteint en un cinquième de
/// seconde de bavardage. Il n'a pas été mesuré directement : lancer une vraie
/// installation modifierait le jeu de l'utilisateur.
///
/// ⚠️ Ce plafond ne couvre **que le bavardage**. Un installateur qui se tairait
/// en restant bloqué ferait toujours attendre l'app indéfiniment — la lecture
/// d'un tube ne rend la main qu'à l'arrivée d'octets ou à sa fermeture. C'est
/// l'état d'avant ce correctif, inchangé, et la seule panne mesurée est le
/// bavardage.
public struct SmapiInstallerLimits: Equatable {
    /// Pourquoi on a coupé — ce que l'appelant doit dire à l'utilisateur.
    public enum Abort: String, Equatable {
        /// L'installateur a produit plus de texte qu'un déroulement normal.
        case tooMuchOutput
        /// Il tourne depuis trop longtemps.
        case timedOut
    }

    public let maxBytes: Int
    public let maxDuration: TimeInterval

    /// Le plafond de production, et une borne de durée large : une
    /// installation réelle se compte en secondes, une minute au plus.
    public static let standard = SmapiInstallerLimits(maxBytes: 1_000_000,
                                                      maxDuration: 600)

    public init(maxBytes: Int, maxDuration: TimeInterval) {
        self.maxBytes = maxBytes
        self.maxDuration = maxDuration
    }

    /// `nil` tant qu'on peut continuer à lire.
    ///
    /// Le volume passe avant la durée : c'est lui qu'on a mesuré, et il dit la
    /// même chose bien plus vite.
    public func abort(bytesRead: Int, elapsed: TimeInterval) -> Abort? {
        if bytesRead > maxBytes { return .tooMuchOutput }
        if elapsed > maxDuration { return .timedOut }
        return nil
    }
}

/// La ligne à montrer quand l'installateur SMAPI échoue.
///
/// Sa sortie de crash se termine par une trace de pile C#, illisible telle
/// quelle : le message utile est la ligne qui annonce l'exception. Extrait de
/// `SmapiInstaller` — c'est la source de **tous** les détails d'erreur que
/// l'utilisateur lit sur cet écran, et elle n'était couverte par aucun test.
public enum SmapiInstallerOutput {
    public static func lastMeaningfulLine(of output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let idx = lines.firstIndex(where: {
            $0.contains("unexpected exception") || $0.contains("failed")
        }) {
            return lines[idx]
        }
        return lines.last(where: { !$0.isEmpty }) ?? "unknown error"
    }
}

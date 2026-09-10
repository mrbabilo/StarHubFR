import Foundation

/// Lecture de `Steam/config/loginusers.vdf` — qui est connecté sur cette
/// machine Steam. La boucle vivait en ligne au cœur de `fetchSteamUser`, sans
/// aucun test ; elle est ici pour en porter un.
///
/// Le format VDF est un format propriétaire de Valve (texte, accolades ou
/// tabulations) ; cette lecture n'en prend que la forme plate que le fichier
/// réel emploie, une paire par ligne indentée.
///
/// ⚠️ **La règle est « dernier vu avant l'arrêt », pas « compte MostRecent ».**
/// La boucle s'arrête à la première ligne `"MostRecent" "1"` rencontrée —
/// comportement historique, conservé tel quel. Le fichier réel range les
/// comptes séquentiellement et le compte récent porte son `PersonaName`
/// avant cette ligne, si bien que l'arrêt tombe juste ; mais un compte
/// antérieur peut avoir fourni l'identifiant ou le nom retenus. Ne pas
/// « corriger » en réécrivant la règle sans avoir mesuré un vrai
/// `loginusers.vdf` multi-comptes.
public struct SteamLoginUsers {
    /// Dernier identifiant `7656…` vu avant l'arrêt, guillemets retirés.
    public let steamID: String
    /// Dernier `PersonaName` vu avant l'arrêt — `""` quand le fichier n'en
    /// dit pas (l'appelant garde alors son propre repli).
    public let personaName: String

    /// Une même lecture pour `loginusers.vdf` entier, déjà lu en chaîne par
    /// l'appelant : le parseur ne touche pas au disque.
    public static func parse(content: String) -> SteamLoginUsers {
        var steamID = ""
        var personaName = ""

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let tLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if tLine.hasPrefix("\"7656") {
                steamID = tLine.replacingOccurrences(of: "\"", with: "")
            }
            if tLine.hasPrefix("\"PersonaName\"") {
                let parts = tLine.components(separatedBy: "\"")
                if parts.count >= 4 { personaName = parts[3] }
            }
            if tLine.hasPrefix("\"MostRecent\"") && tLine.contains("\"1\"") {
                break
            }
        }
        return SteamLoginUsers(steamID: steamID, personaName: personaName)
    }
}

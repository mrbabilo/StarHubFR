import Foundation

/// Ce qu'un mod garde en silence — et ce qui, dans ce silence, nous concerne.
///
/// Le dump Pathoschild porte un champ `warnings` que l'app ignorait
/// entièrement. Il vaut la lecture : télémétrie non divulguée et non annoncée
/// sur la page du mod, plantages au chargement d'une sauvegarde, archive à la
/// structure fausse qu'il faut dézipper deux fois, incompatibilité multijoueur.
///
/// **Mais le remonter tel quel contredirait la source primaire.** Sur les 24
/// avertissements du dump (mesuré le 2026-09-05, 4 720 entrées), **17 ne
/// parlent que d'Android** — « Broken on Android », « Only works on Android » :
/// du bruit pur sur macOS. Les deux exemplaires du parc de référence en font
/// partie, et smapi.io déclare ces deux mods-là `Ok`. Afficher « cassé » sur un
/// mod que la source primaire dit sain, c'est se contredire à l'écran.
///
/// Ce qui manquait n'était donc pas le champ : c'était **la règle qui écarte ce
/// qui ne nous concerne pas**. Elle est ici, et volontairement étroite — un
/// garde trop large perdrait plus que le bruit qu'il retire.
public enum ModPlatformWarnings {

    /// Ce qu'un avertissement concerne.
    public enum Relevance: Equatable, Sendable {
        /// À lire : rien ne dit qu'il ne nous concerne pas.
        case worthReading
        /// Une plateforme qui n'est pas la nôtre, et elle seule.
        case otherPlatform
        /// Un magasin de téléchargement qu'on n'utilise pas — « use Nexus,
        /// ModDrop is NOT updated » : c'est déjà ce que fait l'app.
        case downloadSource
    }

    /// Les plateformes étrangères que le dump nomme.
    ///
    /// Cherchées **en mots entiers**, jamais en sous-chaînes : « ios » vit à
    /// l'intérieur de « ratios » et de « kiosk », et un faux positif de ce
    /// côté-ci *masque* un avertissement réel. C'est le sens dangereux.
    private static let foreignPlatforms =
        #"\b(android|ios|iphone|ipad)\b"#

    /// La nôtre, sous toutes ses écritures — plus les formules qui disent
    /// « partout ». Leur présence **annule** l'écart : « Broken on Android and
    /// macOS » nous concerne, et une recherche d'« android » seule le perdrait.
    ///
    /// Large à dessein : un faux positif ici ne fait qu'**afficher** une ligne
    /// de trop, ce qui se corrige d'un coup d'œil.
    private static let ourPlatform =
        #"\b(mac ?os|mac|os ?x|osx|pc|linux|windows|desktop|all platforms|every platform)\b"#

    /// Ce que cet avertissement concerne.
    ///
    /// L'asymétrie est voulue : on n'écarte que sur un signe **positif** qu'il
    /// s'agit d'ailleurs. Un avertissement qui ne nomme aucune plateforme est
    /// gardé — le silence n'est pas une preuve.
    public static func relevance(of warning: String) -> Relevance {
        let text = warning.lowercased()
        if matches(text, foreignPlatforms), !matches(text, ourPlatform) {
            return .otherPlatform
        }
        // Nommer ModDrop ne suffit pas : « The ModDrop build corrupts saves »
        // est un vrai défaut. Seul le renvoi vers l'autre source est du bruit,
        // et c'est la source qu'on utilise déjà.
        if text.contains("moddrop"), text.contains("nexus") {
            return .downloadSource
        }
        return .worthReading
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Le tamis : ce qui nous concerne, dans l'ordre d'origine, **débarrassé de
    /// son balisage**.
    ///
    /// Deux des six avertissements gardés portent un lien Markdown. La règle de
    /// lecture n'est pas réécrite ici : `ModCompatibility.parseSummary` la
    /// tient déjà pour le champ voisin (`summary`) du même dump, sur le même
    /// balisage. Deux copies auraient divergé — c'est le patron que ce dépôt
    /// paie le plus cher.
    public static func worthReading(_ warnings: [String]) -> [String] {
        warnings.compactMap {
            guard !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  relevance(of: $0) == .worthReading else { return nil }
            let text = ModCompatibility.parseSummary($0).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}

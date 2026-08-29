import Foundation

/// Ce qu'un **nom de fichier téléchargé** dit de sa page Nexus.
///
/// Une traduction glissée sur l'app arrive sans rien derrière elle : pas de
/// fiche Nexus, donc pas d'identifiant, pas de version, pas de lien vers la
/// page — alors que le nom du fichier les porte le plus souvent. Sur le parc du
/// 2026-08-29, **six des dix traductions et greffes enregistrées** avaient un
/// identifiant écrit dans leur nom et un `nexusModId` resté à zéro.
///
/// L'identifiant rendu ici est celui de **l'archive**, pas du mod qui la
/// reçoit : la traduction française de UI Info Suite 2 Alternative est la page
/// Nexus 46333, le mod traduit est la 43127. Il n'a donc rien à faire dans le
/// registre d'identifiants des mods installés.
///
/// Deux formes, relevées sur des archives réelles — aucune n'est une spec
/// publiée, et l'app n'en fabrique aucune :
///
/// 1. **À espaces**, la forme de 2026 : `… <id> <version> <horodatage> <jeton>`,
///    par exemple `UI Info Suite 2 Alternative FR 46333 2.9.0 2026-08-10T13-50Z
///    Pct026wXo`. C'est **l'horodatage** qui ancre la lecture, jamais la
///    position dans la phrase : prendre le premier entier venu rendrait `2`,
///    pris au « Suite 2 » du titre.
/// 2. **À tirets**, la forme ancienne : `<nom>-<id>-<version pointillée>-<date
///    Unix>`, par exemple `MakeGuntherRealFR-34339-1-0-1748539543`. C'est la
///    date Unix finale qui ancre — sans elle, `Quick Chest Categories for
///    Chests Anywhere-1.0.2` se ferait lire comme un identifiant.
///
/// Quand le nom ne dit rien, cette lecture ne dit rien : quatre noms du corpus
/// (`New Item Bags for Sunberry Village`…) tiennent leur identifiant du
/// navigateur intégré, et rien ne doit être inventé à leur place.
public enum NexusArchiveName {

    /// Ce que le nom d'une archive apprend sur sa provenance.
    public struct Origin: Equatable, Sendable {
        public let modId: Int
        /// La version telle que le nom la porte, `""` quand il n'en porte pas.
        public let version: String

        public init(modId: Int, version: String) {
            self.modId = modId
            self.version = version
        }
    }

    /// La date de mise en ligne n'est **pas** lue ici, bien que les deux formes
    /// la portent. `InstalledTranslation.updatedAt` décide à elle seule qu'une
    /// mise à jour existe, et rien ne dit encore que cette date-là soit celle
    /// que Nexus rend pour la page — s'en servir ferait annoncer des mises à
    /// jour qui n'existent pas.
    public static func parse(_ name: String) -> Origin? {
        let stem = withoutArchiveExtension(name)
        return spacedForm(stem) ?? dashedForm(stem)
    }

    /// Les extensions que l'app accepte à l'installation. Le nom relevé par la
    /// feuille d'installation est déjà décapité, mais un appelant pourrait ne
    /// pas l'être — et l'extension collée au jeton final ferait rater la forme.
    private static let archiveExtensions: Set<String> = ["zip", "rar", "7z"]

    private static func withoutArchiveExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."),
              archiveExtensions.contains(String(name[name.index(after: dot)...]).lowercased())
        else { return name }
        return String(name[name.startIndex..<dot])
    }

    /// `… <id> <version> 2026-08-10T13-50Z <jeton>`.
    private static func spacedForm(_ stem: String) -> Origin? {
        let tokens = stem.split(separator: " ").map(String.init)
        guard let stamp = tokens.firstIndex(where: isDatedStamp), stamp >= 2 else { return nil }
        guard let modId = plausibleModId(tokens[stamp - 2]) else { return nil }
        // La version corrobore : un identifiant sans elle serait un entier
        // choisi pour sa seule place, ce qui ne vaut pas mieux que deviner.
        let version = tokens[stamp - 1]
        guard version.first?.isNumber == true else { return nil }
        return Origin(modId: modId, version: version)
    }

    /// `<nom>-<id>-<version en tirets>-<date Unix>`.
    private static func dashedForm(_ stem: String) -> Origin? {
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, isUnixStamp(parts[parts.count - 1]) else { return nil }
        // Le nom occupe toujours la première tranche — un mod qui s'appellerait
        // d'un nombre n'y donnerait pas son identifiant.
        let tail = parts[1..<(parts.count - 1)]
        guard let idIndex = tail.indices.first(where: { plausibleModId(tail[$0]) != nil }),
              let modId = plausibleModId(tail[idIndex])
        else { return nil }
        let version = tail[(idIndex + 1)...].joined(separator: ".")
        return Origin(modId: modId, version: version)
    }

    /// `2026-08-10T13-50Z` — l'horodatage de la forme à espaces, à la minute.
    private static func isDatedStamp(_ token: String) -> Bool {
        let shape: [Character] = Array("0000-00-00T00-00Z")
        guard token.count == shape.count else { return false }
        for (character, model) in zip(token, shape) {
            if model == "0" {
                guard character.isNumber else { return false }
            } else if character != model {
                return false
            }
        }
        return true
    }

    /// Dix chiffres : une date Unix en secondes, donc postérieure à 2001. C'est
    /// ce qui distingue la forme à tirets d'un simple nom qui en contient.
    private static func isUnixStamp(_ token: String) -> Bool {
        token.count == 10 && token.allSatisfy(\.isNumber)
    }

    /// Un identifiant de page Nexus : des chiffres, et pas une date déguisée.
    private static func plausibleModId(_ token: String) -> Int? {
        guard token.count <= 7, token.allSatisfy(\.isNumber),
              let value = Int(token), value > 0
        else { return nil }
        return value
    }
}

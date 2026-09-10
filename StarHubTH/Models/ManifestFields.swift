import Foundation

/// Lecture des champs d'un `manifest.json` déjà décodé.
///
/// Cette lecture était écrite **trois fois** : les deux branches de
/// `parseModFolder` (cache chaud / lecture disque) et `ModManifest.init?(dict:)`.
/// Elles ont déjà divergé une fois — sur le champ `Version`, si bien qu'un même
/// mod rendait deux chaînes différentes selon que son manifeste venait du cache
/// ou du disque. Trois copies d'une même règle divergent à la première retouche.
///
/// ⚠️ **Les champs sont rendus bruts, sans repli.** Le scan retombe sur le nom
/// **logique du dossier** quand `Name` manque, et ce nom n'existe pas ici ;
/// `ModManifest`, lui, refuse purement le manifeste. Poser un défaut à cet
/// endroit remplacerait le premier en silence et déplacerait la garde du
/// second. `nil` veut dire « le manifeste ne dit rien », pas « vide » : un
/// `"Name": ""` reste une chaîne vide, que `ModManifest` accepte.
public struct ManifestFields {
    public let name: String?
    public let uniqueId: String?
    public let version: String?
    public let author: String?
    public let description: String?
    public let updateKeys: [String]
    public let dependencies: [ModDependency]
    /// `nil` quand aucune `UpdateKey` ne porte d'identifiant Nexus valide —
    /// l'appelant choisit sa propre sentinelle plutôt qu'un id vide.
    public let nexus: (id: String, url: String)?

    public init(manifest: [String: Any]) {
        name = manifest.caseInsensitiveValue(forKey: "Name") as? String
        uniqueId = manifest.caseInsensitiveValue(forKey: "UniqueID") as? String
        author = manifest.caseInsensitiveValue(forKey: "Author") as? String
        description = manifest.caseInsensitiveValue(forKey: "Description") as? String
        // Les trois champs composés passent par leur source unique — la forme
        // objet de `Version`, `ContentPackFor` pour les dépendances, la
        // tolérance casse/espaces/`@variante` pour l'identifiant Nexus.
        version = ManifestVersionReader.version(from: manifest)
        dependencies = ModDependencyParser.parse(manifest: manifest)
        updateKeys = manifest.caseInsensitiveValue(forKey: "UpdateKeys") as? [String] ?? []
        nexus = ModManifest.parseNexusId(fromUpdateKeys: updateKeys)
    }

    /// `UpdateCautionMessage` — extension **Stardrop** du manifeste, ignorée
    /// par SMAPI : l'auteur y annonce ce que sa mise à jour casse. Trim, et un
    /// message blanc vaut absent (Stardrop : `IsNullOrEmpty`) — un message
    /// d'espaces n'alerte pas plus qu'un champ vide.
    ///
    /// **Hors de l'initialiseur à dessein** : seule la fiche d'un mod à
    /// installer le lit, alors que le scan construit un `ManifestFields` par
    /// manifeste du parc. Mesuré le 2026-09-10 : le lire pour tout le monde
    /// coûtait 1,6 ms des 17,5 ms de lecture d'un scan complet (1 108
    /// manifestes) — pour un champ qu'**aucun** d'entre eux ne porte. Le
    /// chemin lent est celui d'un champ absent : `caseInsensitiveValue`
    /// balaie alors toutes les clés en les minusculant.
    public static func updateCautionMessage(in manifest: [String: Any]) -> String? {
        guard let caution = manifest.caseInsensitiveValue(forKey: "UpdateCautionMessage") as? String,
              !caution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return caution
    }
}

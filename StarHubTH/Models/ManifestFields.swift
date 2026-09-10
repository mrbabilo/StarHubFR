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
    /// `UpdateCautionMessage` — extension **Stardrop** ignorée par SMAPI.
    /// Seul champ portant une politique : trim, et blanc vaut absent.
    public let updateCautionMessage: String?

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

        if let caution = manifest.caseInsensitiveValue(forKey: "UpdateCautionMessage") as? String,
           !caution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateCautionMessage = caution
        } else {
            updateCautionMessage = nil
        }
    }
}

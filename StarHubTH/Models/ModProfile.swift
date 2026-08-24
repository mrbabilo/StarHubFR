import Foundation

/// Ce que le profil retient d'un mod en plus de son identifiant.
///
/// Un profil ne stockait que des `UniqueID` opaques. Le jour où le mod n'est
/// plus installé, plus rien ne permet d'en dire quoi que ce soit : ni son nom,
/// ni où le retrouver. Ces deux champs sont connus au moment où le mod entre
/// dans le profil — ils étaient simplement jetés.
struct ProfileModMetadata: Codable, Hashable {
    let name: String
    /// Vide quand le manifeste ne déclare pas de clé de mise à jour Nexus.
    let nexusModId: String

    init(name: String, nexusModId: String) {
        self.name = name
        self.nexusModId = nexusModId
    }
}

struct ModProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Les mods actifs du profil, par `UniqueID`. Reste la seule source
    /// d'appartenance : `modMetadata` ne fait que décrire.
    var enabledModIds: [String] // Array of uniqueIds
    /// `UniqueID` → ce qu'on savait du mod quand il est entré dans le profil.
    /// Vide pour les profils enregistrés avant le 2026-08-24.
    var modMetadata: [String: ProfileModMetadata] = [:]

    init(id: UUID = UUID(),
         name: String,
         enabledModIds: [String],
         modMetadata: [String: ProfileModMetadata] = [:]) {
        self.id = id
        self.name = name
        self.enabledModIds = enabledModIds
        self.modMetadata = modMetadata
    }

    /// Décodage tolérant à l'absence de `modMetadata` : les profils déjà
    /// enregistrés chez l'utilisateur ne le portent pas, et un décodage strict
    /// les ferait tous disparaître au premier lancement de cette version.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabledModIds = try container.decode([String].self, forKey: .enabledModIds)
        modMetadata = try container.decodeIfPresent([String: ProfileModMetadata].self,
                                                    forKey: .modMetadata) ?? [:]
    }
}

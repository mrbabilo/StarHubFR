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
    /// `UniqueID` → note libre, pour se souvenir *pourquoi* (« désactivé en
    /// multi car désync »). Vide pour les profils enregistrés avant les notes
    /// (B3-T6). Suit l'identité du mod, pas son dossier — une note survit à
    /// une mise en pause.
    var modNotes: [String: String] = [:]

    init(id: UUID = UUID(),
         name: String,
         enabledModIds: [String],
         modMetadata: [String: ProfileModMetadata] = [:],
         modNotes: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.enabledModIds = enabledModIds
        self.modMetadata = modMetadata
        self.modNotes = modNotes
    }

    /// Décodage tolérant à l'absence de `modMetadata` et de `modNotes` : les
    /// profils déjà enregistrés chez l'utilisateur ne les portent pas, et un
    /// décodage strict les ferait tous disparaître au premier lancement de
    /// cette version.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabledModIds = try container.decode([String].self, forKey: .enabledModIds)
        modMetadata = try container.decodeIfPresent([String: ProfileModMetadata].self,
                                                    forKey: .modMetadata) ?? [:]
        modNotes = try container.decodeIfPresent([String: String].self,
                                                 forKey: .modNotes) ?? [:]
    }
}

extension ModProfile {
    /// La note libre du mod dans **ce** profil, s'il y en a une.
    func note(forModId uniqueId: String) -> String? {
        guard !uniqueId.isEmpty else { return nil }
        return modNotes[uniqueId].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Écrit la note du mod dans **ce** profil. Une note vidée (ou `nil`) est
    /// **retirée** : un mod jamais noté ne doit pas laisser de clé morte dans
    /// le JSON du profil. Un identifiant vide ne note rien — l'en-tête d'un
    /// pack n'a pas d'identité (F4), ses composants se notent eux-mêmes.
    mutating func setNote(_ text: String?, forModId uniqueId: String) {
        guard !uniqueId.isEmpty else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            modNotes.removeValue(forKey: uniqueId)
        } else {
            modNotes[uniqueId] = trimmed
        }
    }
}

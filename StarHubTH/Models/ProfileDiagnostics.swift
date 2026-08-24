import Foundation

/// Un mod qu'un profil réclame et qui n'est plus installé.
struct MissingProfileMod: Identifiable, Equatable {
    var id: String { uniqueId }
    let uniqueId: String
    /// Le nom, quand une source le connaît encore. `nil` n'est pas une
    /// anomalie : un mod désinstallé ne laisse rien derrière lui si le profil
    /// n'a pas retenu son nom.
    let name: String?
    /// L'identifiant Nexus, quand il est connu — la seule chose qui rende le
    /// mod téléchargeable depuis l'app.
    let nexusModId: String?
    /// Une sauvegarde du dossier existe : le mod se récupère sans réseau.
    let hasBackup: Bool
    /// Livré **avec** SMAPI : il revient par une réinstallation de SMAPI, pas
    /// par Nexus.
    let isBundledWithSmapi: Bool

    /// Ce qu'on affiche : le nom connu, sinon l'identifiant rendu lisible.
    var displayName: String {
        name ?? ProfileDiagnostics.readableName(from: uniqueId)
    }
}

/// Ce qu'un profil peut dire de lui-même une fois confronté au disque.
///
/// Le calcul vivait dans `applyProfileToFilesystem`, où il n'alimentait qu'une
/// alerte de fin d'application. Il est ici pour que l'alerte et l'écran des
/// mods manquants lisent **la même source** — deux mécanismes voisins auraient
/// fini par annoncer des choses différentes.
enum ProfileDiagnostics {
    /// Les mods du profil absents du disque, dans l'ordre du profil.
    ///
    /// - Parameters:
    ///   - installedUniqueIds: les identifiants trouvés au dernier scan.
    ///   - backupNames: `uniqueId` (en minuscules) → nom, tiré de l'index des
    ///     sauvegardes. Rattrape les profils d'avant l'enregistrement des noms.
    ///   - nexusHints: `uniqueId` (en minuscules) → nom et identifiant Nexus,
    ///     tirés du cache des mises à jour.
    static func missingMods(in profile: ModProfile,
                            installedUniqueIds: Set<String>,
                            backupNames: [String: String],
                            nexusHints: [String: ProfileModMetadata]) -> [MissingProfileMod] {
        // La comparaison ignore la casse : SMAPI lui-même traite les
        // `UniqueID` ainsi, et un manifeste réédité avec une majuscule
        // différente ferait autrement passer un mod installé pour disparu.
        let installed = Set(installedUniqueIds.map { $0.lowercased() })
        return profile.enabledModIds.compactMap { uniqueId in
            let key = uniqueId.lowercased()
            guard !installed.contains(key) else { return nil }
            let remembered = profile.modMetadata[uniqueId] ?? profile.modMetadata[key]
            let hint = nexusHints[key]
            let backupName = backupNames[key]
            return MissingProfileMod(
                uniqueId: uniqueId,
                // Ce que le profil a retenu prime : c'était vrai au moment où
                // le mod y est entré.
                name: remembered?.name ?? hint?.name ?? backupName,
                nexusModId: nonEmpty(remembered?.nexusModId) ?? nonEmpty(hint?.nexusModId),
                hasBackup: backupName != nil,
                isBundledWithSmapi: isBundledWithSmapi(uniqueId))
        }
    }

    /// Un identifiant rendu lisible, faute de nom : on garde le dernier
    /// segment — le préfixe est l'auteur — et on sépare les mots collés.
    /// `ThaleTheGreat.WalletToolsForTractorMod` → `Wallet Tools For Tractor Mod`.
    static func readableName(from uniqueId: String) -> String {
        let leaf = uniqueId.split(separator: ".").last.map(String.init) ?? uniqueId
        var words: [String] = []
        var current = ""
        for character in leaf {
            // Une majuscule ouvre un mot, sauf en tête ou à la suite d'une
            // autre majuscule : `FTM` et `PeliQ` restent d'un seul tenant.
            if character.isUppercase, let previous = current.last, !previous.isUppercase {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }

    /// Les mods que l'installateur de SMAPI dépose lui-même dans `Mods/`.
    static func isBundledWithSmapi(_ uniqueId: String) -> Bool {
        uniqueId.lowercased().hasPrefix("smapi.")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

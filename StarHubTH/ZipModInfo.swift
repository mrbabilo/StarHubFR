import Foundation

/// Manifest information extracted from manifest.json
struct ModManifest {
    let name: String
    let version: String
    let uniqueId: String
    let author: String
    let description: String
    let nexusModId: String
    let nexusUrl: String
    let dependencies: [ModDependency]

    /// Parses the first valid Nexus mod id from a manifest's `UpdateKeys`
    /// array. Centralized here (and exposed publicly) so every call site
    /// (manifest parsing in `ZipModInfo`, on-the-fly scan in
    /// `StarHubTHViewModel`, future repair flows) shares one implementation.
    ///
    /// Accepts the SMAPI/Nexus conventions:
    ///   - `nexus:191`          → id "191"
    ///   - `Nexus: 191 `        → id "191" (whitespace + case tolerant)
    ///   - `Nexus:23169@SwimItems` → id "23169" (drops `@variant` suffix)
    ///
    /// Returns `nil` when no valid positive integer id is found, so callers
    /// can treat the mod as "no Nexus link" without a sentinel empty string.
    ///
    /// - Returns: Tuple `(id, url)` where `url` is the canonical
    ///   `nexusmods.com/games/stardewvalley/mods/<id>` link, or `nil`.
    public static func parseNexusId(fromUpdateKeys keys: [String]?) -> (id: String, url: String)? {
        guard let keys else { return nil }
        for raw in keys {
            // Trim leading/trailing whitespace BEFORE the prefix check, so a
            // key like "  Nexus:240" still matches. (Previously the un-trimmed
            // string was tested and leading whitespace silently rejected the
            // entry — the same latent bug existed in both pre-refactor sites.)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("nexus:") else { continue }
            var id = trimmed.replacingOccurrences(of: "nexus:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop a `@variant` suffix used by multi-mod packs sharing one
            // Nexus id (e.g. `Nexus:23169@SwimItems`).
            if let atIndex = id.firstIndex(of: "@") {
                id = String(id[..<atIndex])
            }
            id = id.trimmingCharacters(in: .whitespacesAndNewlines)
            // Reject non-numeric, zero, or negative ids — they would only
            // produce 404s / garbage from the Nexus API.
            guard let num = Int(id), num > 0 else { continue }
            return (id, "https://www.nexusmods.com/stardewvalley/mods/\(id)")
        }
        return nil
    }

    /// Le nom à afficher sur une ligne de mise à jour.
    ///
    /// Le nom **installé** d'abord — celui que le mod déclare dans son
    /// manifest, donc celui que la liste des mods affiche déjà. Un même mod ne
    /// doit pas changer de nom d'un écran à l'autre.
    ///
    /// Le nom de la liste de compatibilité SMAPI ensuite : il manque pour la
    /// plupart des mods (15 des 23 mises à jour du parc réel n'en avaient
    /// aucun) et porte parfois un renommage — « Kids for the School → Kids for
    /// the School Tokens » — qui n'est pas un nom d'affichage.
    ///
    /// L'`UniqueID` en dernier recours seulement. C'était le repli immédiat, et
    /// il s'affichait donc sur ces 15 lignes : « xzqute.ChoreTrail » à la place
    /// de « ChoreTrail ».
    ///
    /// Un nom vide ou blanc ne gagne pas : il laisserait une ligne sans
    /// étiquette, ce qu'aucune des trois sources ne vaut.
    public static func resolveDisplayName(installedName: String?,
                                          metadataName: String?,
                                          uniqueId: String) -> String {
        for candidate in [installedName, metadataName] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
        }
        return uniqueId
    }

    /// L'identifiant Nexus d'une ligne de mise à jour, ou `nil` si le mod n'a
    /// pas de page Nexus.
    ///
    /// `metadata.nexusID` d'abord — c'est smapi.io qui parle. Mais elle ne le
    /// connaît que pour les mods de sa liste de compatibilité : mesuré sur le
    /// parc réel, **15 des 23 mises à jour n'en avaient aucun**, alors que
    /// toutes déclaraient un `Nexus:<id>` dans leur manifest. Sans ce repli,
    /// l'appelant retombait sur l'`UniqueID` — non numérique — et le bouton de
    /// téléchargement disparaissait de la ligne.
    ///
    /// La clé déclarée passe par `parseNexusId`, donc hérite de sa tolérance
    /// (casse, espaces, suffixe `@variante`) et de son refus des identifiants
    /// nuls ou négatifs. Un `metadata.nexusID` non positif ne l'emporte pas :
    /// il ne mènerait qu'à un 404.
    ///
    /// `nil` plutôt qu'une chaîne vide : un mod suivi seulement par GitHub ou
    /// CurseForge n'a rien à proposer au téléchargement, et l'appelant choisit
    /// sa propre sentinelle.
    public static func resolveNexusId(metadataNexusID: Int?, updateKeys: [String]?) -> String? {
        if let id = metadataNexusID, id > 0 { return String(id) }
        return parseNexusId(fromUpdateKeys: updateKeys)?.id
    }

    init?(dict: [String: Any]) {
        guard let name = dict.caseInsensitiveValue(forKey: "Name") as? String,
              let uniqueId = dict.caseInsensitiveValue(forKey: "UniqueID") as? String else {
            return nil
        }
        
        self.name = name
        self.uniqueId = uniqueId
        
        if let author = dict.caseInsensitiveValue(forKey: "Author") as? String {
            self.author = author
        } else {
            self.author = "Unknown"
        }
        
        if let ver = dict.caseInsensitiveValue(forKey: "Version") as? String {
            self.version = ver
        } else if let verDict = dict.caseInsensitiveValue(forKey: "Version") as? [String: Any] {
            let major = verDict.caseInsensitiveValue(forKey: "MajorVersion") as? Int ?? 1
            let minor = verDict.caseInsensitiveValue(forKey: "MinorVersion") as? Int ?? 0
            let patch = verDict.caseInsensitiveValue(forKey: "PatchVersion") as? Int ?? 0
            self.version = "\(major).\(minor).\(patch)"
        } else {
            self.version = "Unknown"
        }

        self.description = dict.caseInsensitiveValue(forKey: "Description") as? String ?? ""

        // Parse Nexus mod id from UpdateKeys via the shared helper so the
        // scanning logic stays in one place (also used by
        // `StarHubTHViewModel.parseModFolder`).
        let updateKeys = dict.caseInsensitiveValue(forKey: "UpdateKeys") as? [String]
        if let nexus = Self.parseNexusId(fromUpdateKeys: updateKeys) {
            self.nexusModId = nexus.id
            self.nexusUrl = nexus.url
        } else {
            self.nexusModId = ""
            self.nexusUrl = ""
        }
        
        var deps: [ModDependency] = []
        if let depArray = dict.caseInsensitiveValue(forKey: "Dependencies") as? [[String: Any]] {
            for dep in depArray {
                if let depId = dep.caseInsensitiveValue(forKey: "UniqueID") as? String {
                    let isReq = dep.caseInsensitiveValue(forKey: "IsRequired") as? Bool ?? true
                    deps.append(ModDependency(uniqueId: depId, isRequired: isReq))
                }
            }
        }
        self.dependencies = deps
    }
}

/// Validation status of a zip file
enum ValidationStatus {
    case valid
    case invalidStructure
    case oversized
    case tooManyMods
    case corrupted
    /// L'archive est lisible, mais son format n'est pas géré. Distinct de
    /// `.corrupted` : annoncer « archive corrompue » sur un `.7z` parfaitement
    /// sain envoie l'utilisateur chercher un problème qui n'existe pas.
    case unsupportedFormat(String)
}

extension ValidationStatus {
    /// Le conseil à donner après un refus — ou `nil` quand il n'y a rien
    /// d'utile à dire.
    ///
    /// Le conseil doit correspondre à la **raison** du refus. Suggérer de
    /// retélécharger n'a de sens que pour une archive réellement abîmée : une
    /// archive intacte qui n'est simplement pas un mod renverrait l'utilisateur
    /// retélécharger indéfiniment un fichier parfaitement valide. C'est le cas
    /// vécu sur `Cloth And Colors Bag` (Nexus 50108) — une archive de 1,4 Ko
    /// contenant un unique fichier de configuration pour ItemBags, à déposer
    /// dans le dossier de ce mod-là.
    ///
    /// Même principe que la distinction `.unsupportedFormat` / `.corrupted`
    /// ci-dessus, appliqué au cas qui restait.
    var recoveryHintKey: String? {
        switch self {
        case .corrupted:
            return L10n.ModInstall.recoverZip
        case .invalidStructure:
            return L10n.ModInstall.notAModHint
        case .valid, .oversized, .tooManyMods, .unsupportedFormat:
            return nil
        }
    }
}

/// Type of conflict detected during installation
enum ConflictType: Equatable {
    case folderExists
    case configFilesConflict
    case dependencyMissing
}

/// Available resolutions for conflicts
enum ConflictResolution: Hashable {
    case overwriteWithBackup
    case rename
    case skip
    case keepExisting
    case useNew
}

/// Conflict detected during mod installation
struct ModConflict: Identifiable {
    let id = UUID()
    let conflictType: ConflictType
    let folderName: String
    let existingVersion: String
    let newVersion: String
    let resolutionOptions: [ConflictResolution]
}

/// A single mod detected inside a zip file
struct DetectedMod: Identifiable {
    let id = UUID()
    let folderName: String
    let relativePath: String
    let manifest: ModManifest
    let hasConfigFiles: Bool
    let dependencies: [String]
    let dependencyDetails: [ModDependency]
    let existingVersion: ModItem?
    
    var uniqueId: String { manifest.uniqueId }
    var name: String { manifest.name }
    var version: String { manifest.version }
    var author: String { manifest.author }
    var nexusModId: String { manifest.nexusModId }
    var nexusUrl: String { manifest.nexusUrl }
    var modDescription: String { manifest.description }
}

/// Information extracted from a zip file before installation
struct ZipModInfo: Identifiable {
    let id = UUID()
    let zipName: String
    let detectedMods: [DetectedMod]
    let validationStatus: ValidationStatus
    /// Contenu de premier niveau de l'archive, renseigné seulement quand aucune
    /// structure de mod n'a été reconnue — c'est là qu'il est utile.
    var extractedTopLevel: [String] = []
    let conflicts: [ModConflict]
    let estimatedSize: Int64
    
    var isValid: Bool {
        if case .valid = validationStatus {
            return true
        }
        return false
    }
    
    var hasConflicts: Bool {
        !conflicts.isEmpty
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
    }
}

/// Resolution selection for a mod during installation
struct InstallSelection {
    let modId: UUID
    let selected: Bool
    let conflictResolution: ConflictResolution?
    let configResolution: ConfigResolution?
}

/// Resolution for config file conflicts
enum ConfigResolution: Hashable {
    case keepExisting
    case useNew
    case merge
}
import Foundation

/// Le `config.json` d'un mod, tel qu'un profil l'a mémorisé.
///
/// Le texte, jamais une structure décodée. `JSONSerialization` rend un
/// dictionnaire **non ordonné** : y faire un aller-retour mélangerait les clés,
/// alors que SMAPI les écrit dans l'ordre des champs de sa classe C# (mesuré
/// sur le parc réel : 1 config sur 79 seulement se trouve en ordre
/// alphabétique). Mémoriser le texte préserve l'ordre sans rien parser — et
/// avale au passage les configs qui ne se parsent pas du tout (2 mesurés).
public struct ProfileConfigEntry: Codable, Equatable, Sendable {
    public let text: String
    public let capturedAt: Date

    public init(text: String, capturedAt: Date) {
        self.text = text
        self.capturedAt = capturedAt
    }
}

/// Ce qu'un profil retient des `config.json` des mods qu'on lui a confiés.
///
/// Un fichier par profil, sur disque, au précédent de
/// `TranslationCoverageCache` — pas dans `UserDefaults`, où les profils vivent
/// déjà en un seul blob et où un config de 45 Ko n'a rien à faire.
///
/// La clé est le nom **logique** du dossier du mod (`ModItem.folderName`,
/// chemin relatif depuis `Mods/`, sans le point de mise en pause) et non
/// l'`UniqueID` : un config vit dans un dossier, pas dans une identité, et le
/// parc réel porte un `UniqueID` installé dans deux dossiers que l'identité
/// confondrait. C'est déjà la clé de `ModConfigBackupItem`, pour la même
/// raison. Divergence assumée avec `ModProfile.modNotes`, qui suit l'identité
/// parce qu'une note doit survivre à une mise en pause.
public enum ProfileConfigStore {

    /// Le fichier du magasin pour ce profil. `nil` si Application Support est
    /// introuvable — le magasin est alors simplement inopérant, jamais fautif.
    public static func fileURL(profileId: UUID,
                               fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first else { return nil }
        let dir = base
            .appendingPathComponent("StarHubTH", isDirectory: true)
            .appendingPathComponent("ProfileConfigs", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(profileId.uuidString).json")
    }

    /// Relit le magasin d'un profil. Un fichier absent ou illisible rend un
    /// magasin **vide** plutôt qu'une erreur : le pire qu'il puisse arriver est
    /// de ne rien restaurer, jamais d'écrire n'importe quoi dans un mod.
    public static func load(from url: URL,
                            fileManager: FileManager = .default) -> [String: ProfileConfigEntry] {
        guard let data = fileManager.contents(atPath: url.path),
              let decoded = try? JSONDecoder().decode([String: ProfileConfigEntry].self,
                                                      from: data)
        else { return [:] }
        return decoded
    }

    /// Écrit le magasin. Atomique, et silencieux en cas d'échec : le magasin
    /// est un souvenir, pas la donnée de l'utilisateur — celle-ci est dans le
    /// mod.
    public static func save(_ entries: [String: ProfileConfigEntry], to url: URL) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Le magasin après capture du config d'un mod.
    ///
    /// Fonction **pure** : elle ne lit ni n'écrit rien. L'appelant lui donne ce
    /// que porte le disque (`nil` si le fichier n'existe pas) et reçoit le
    /// magasin qu'il devrait enregistrer. Trois règles, toutes issues du §6.1
    /// de la spec :
    ///
    /// - un config **absent** *retire* l'entrée : le bouton « Repartir des
    ///   réglages par défaut » supprime le fichier, et sans cette règle revenir
    ///   au profil le ferait ressusciter ;
    /// - un texte **identique** à ce qui est déjà mémorisé ne touche pas
    ///   l'entrée, `capturedAt` compris — une date rafraîchie pour une capture
    ///   qui n'a rien changé afficherait de l'activité là où il n'y en a pas ;
    /// - sinon l'entrée est remplacée, texte et date.
    public static func captured(_ entries: [String: ProfileConfigEntry],
                                folderName: String,
                                diskText: String?,
                                now: Date) -> [String: ProfileConfigEntry] {
        var out = entries
        guard let diskText else {
            out.removeValue(forKey: folderName)
            return out
        }
        if entries[folderName]?.text == diskText { return out }
        out[folderName] = ProfileConfigEntry(text: diskText, capturedAt: now)
        return out
    }

    // MARK: - Les magasins sans propriétaire (B3-T7)

    /// Le dossier qui porte les magasins. `nil` si Application Support est
    /// introuvable — comme `fileURL`, qui le construit de la même façon.
    public static func directoryURL(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first else { return nil }
        return base
            .appendingPathComponent("StarHubTH", isDirectory: true)
            .appendingPathComponent("ProfileConfigs", isDirectory: true)
    }

    /// Efface le magasin d'un profil. Un fichier déjà absent n'est pas une
    /// erreur : la fonction dit seulement si quelque chose a disparu.
    ///
    /// Supprimer un profil est irréversible et son magasin n'est sauvegardé
    /// nulle part : c'est le dialogue de confirmation, en amont, qui prévient.
    ///
    /// Un effacement qui échoue — dossier verrouillé, droits refusés — ne
    /// remonte nulle part, et c'est tenable ici : le profil, lui, a disparu
    /// des préférences, donc le fichier est devenu un orphelin et le balayage
    /// du prochain démarrage le reprendra. La panne se répare seule au lieu
    /// d'ouvrir une alerte sur un fichier que l'utilisateur ne voit pas.
    @discardableResult
    public static func delete(profileId: UUID,
                              fileManager: FileManager = .default) -> Bool {
        guard let url = fileURL(profileId: profileId, fileManager: fileManager),
              fileManager.fileExists(atPath: url.path) else { return false }
        return (try? fileManager.removeItem(at: url)) != nil
    }

    /// Parmi ces noms de fichiers, ceux qui sont des magasins dont plus aucun
    /// profil ne réclame la propriété.
    ///
    /// Fonction **pure** : le parcours du dossier et l'effacement restent à
    /// l'appelant. Trois règles, chacune tenue par un test.
    ///
    /// - Une liste de profils **vide** ne rend jamais d'orphelin. Des
    ///   préférences illisibles donnent exactement cette liste, et sans cette
    ///   règle le balayage effacerait tout le dossier.
    /// - Seuls les noms de la forme `<UUID>.json` sont candidats : un fichier
    ///   qu'on ne reconnaît pas n'est pas à nous, et ne s'efface pas.
    /// - La comparaison ignore la casse : le nom vient du disque, pas de
    ///   `UUID.uuidString`, et un magasin vivant ne doit pas passer pour
    ///   orphelin sur une différence de casse.
    public static func orphanFileNames(in fileNames: [String],
                                       knownProfileIds: Set<UUID>) -> [String] {
        guard !knownProfileIds.isEmpty else { return [] }
        let known = Set(knownProfileIds.map { $0.uuidString.lowercased() })
        return fileNames.filter { name in
            guard name.hasSuffix(".json") else { return false }
            let stem = String(name.dropLast(5))
            guard UUID(uuidString: stem) != nil else { return false }
            return !known.contains(stem.lowercased())
        }
    }

    /// Le `config.json` d'un mod sur le disque.
    ///
    /// Prend le nom **physique** du dossier (`ModItem.physicalFolderName`),
    /// pas le nom logique qui sert de clé : un mod en pause vit dans un dossier
    /// préfixé par un point, et les confondre écrirait à côté.
    public static func configURL(modsPath: String,
                                 physicalFolderName: String) -> URL {
        URL(fileURLWithPath: modsPath, isDirectory: true)
            .appendingPathComponent(physicalFolderName, isDirectory: true)
            .appendingPathComponent("config.json")
    }
}

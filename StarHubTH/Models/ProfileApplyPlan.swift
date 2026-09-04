import Foundation

/// Ce qu'appliquer un profil demande au disque : la liste des dossiers à
/// renommer, et rien d'autre.
///
/// Le calcul vivait à l'intérieur d'`applyProfileToFilesystem`, mêlé au
/// `DispatchQueue`, aux renommages et au rescane — donc hors de portée de
/// `swift test`. C'est pourtant la moitié qui décide : quels mods bougent, et
/// surtout **lesquels ne bougent pas**. Il est ici pour que la règle soit
/// vérifiable, notamment sa propriété d'idempotence (appliquer deux fois le
/// même profil = l'appliquer une fois).
enum ProfileApplyPlan {

    /// Le sens d'un renommage. Le disque ne connaît que le préfixe point ;
    /// c'est ici qu'il porte un nom.
    enum Direction: Equatable {
        /// `Mods/.X` → `Mods/X`.
        case enable
        /// `Mods/X` → `Mods/.X`.
        case disable
    }

    /// Un renommage à faire dans `Mods/`. `source` et `destination` sont des
    /// noms **physiques** (le point y vit) relatifs à `Mods/` : l'appelant les
    /// joint au chemin du dossier.
    struct Move: Equatable {
        /// Le nom **logique** du mod (jamais de point) — la clé des magasins
        /// persistés, notamment l'horodatage d'activation.
        let folderName: String
        /// Le nom affiché, pour le journal et l'alerte de fin.
        let modName: String
        let source: String
        let destination: String
        let direction: Direction
    }

    /// Les renommages qui feraient correspondre `Mods/` au profil.
    ///
    /// Les mises en pause viennent **avant** les activations : c'est ce qui
    /// libère un nom de dossier avant qu'un autre mod ne le réclame.
    ///
    /// - Parameter installedMods: les mods de **tête** du dernier scan (les
    ///   composants d'un pack ne bougent pas seuls — leur dossier vit dans
    ///   celui du pack).
    static func moves(applying profile: ModProfile, to installedMods: [ModItem]) -> [Move] {
        let toDisable = installedMods.filter {
            $0.isEnabled && isManageable($0) && !isCovered($0, by: profile)
        }
        let toEnable = installedMods.filter { !$0.isEnabled && isCovered($0, by: profile) }

        return toDisable.map { mod in
            Move(folderName: mod.folderName,
                 modName: mod.name,
                 source: mod.physicalFolderName,
                 // Le nom **logique**, jamais le physique : les deux sont
                 // égaux ici (seul un mod actif entre dans cette liste), mais
                 // préfixer un nom physique donnerait `..X` le jour où la
                 // condition du filtre bougerait.
                 destination: "." + mod.folderName,
                 direction: .disable)
        } + toEnable.map { mod in
            Move(folderName: mod.folderName,
                 modName: mod.name,
                 source: mod.physicalFolderName,
                 destination: mod.folderName,
                 direction: .enable)
        }
    }

    /// Le profil réclame ce mod — ou, pour un pack, **au moins un** de ses
    /// composants. Un pack ne se renomme qu'en entier.
    static func isCovered(_ mod: ModItem, by profile: ModProfile) -> Bool {
        if mod.isGroup, let children = mod.children {
            return children.contains { profile.enabledModIds.contains($0.uniqueId) }
        }
        return profile.enabledModIds.contains(mod.uniqueId)
    }

    /// Un profil ne retient que des `UniqueID` : un mod dont le manifeste n'en
    /// déclare pas ne pourra **jamais** être « couvert ». Sans cette garde,
    /// appliquer n'importe quel profil balaierait tous ces mods dans les mods
    /// en pause — une perte silencieuse. On les laisse exactement où ils sont.
    static func isManageable(_ mod: ModItem) -> Bool {
        if mod.isGroup, let children = mod.children {
            return children.contains { !$0.uniqueId.isEmpty }
        }
        return !mod.uniqueId.isEmpty
    }
}

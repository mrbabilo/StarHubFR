import Foundation

/// Qui l'emporte, dans le bandeau d'une fiche de sauvegarde, entre l'icône
/// posée par l'utilisateur et le visage illustré du fermier.
///
/// La règle « toute icône personnalisée passe devant » était trop large : les
/// préréglages (`preset:person`, `preset:leaf`…) sont des **pictogrammes
/// génériques**, hérités d'avant les illustrations, strictement moins
/// informatifs que le portrait qu'ils remplaçaient. Une sauvegarde du parc en
/// portait un, et son bandeau a échangé un visage contre une silhouette.
///
/// Seule une **vraie image** choisie par l'utilisateur est un meilleur
/// portrait que l'illustration. Les préréglages restent affichés partout où
/// ils l'ont toujours été — les lignes de la liste —, ils ne prennent
/// simplement pas la place du grand portrait.
public enum SaveHeroPortrait {

    /// Préfixe des pictogrammes préréglés dans `customIconPath`.
    public static let presetPrefix = "preset:"

    /// - Returns: `true` seulement si `iconPath` désigne une image réelle.
    public static func prefersCustomIcon(_ iconPath: String) -> Bool {
        let trimmed = iconPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.hasPrefix(presetPrefix)
    }
}

extension SaveHeroPortrait {

    /// Le chemin où l'image vit **aujourd'hui**.
    ///
    /// `selectCustomAvatar` enregistre un chemin **absolu** dans `SaveNotes_v2`.
    /// F5 a déplacé `Avatars/` de `StarHubTH/` vers `StarHubFR/` : le chemin
    /// stocké pendouille, et `NSImage(contentsOfFile:)` retombe **en silence**
    /// sur le pictogramme générique — l'avatar disparaît sans un mot.
    ///
    /// La résolution se fait à la lecture plutôt qu'en réécrivant la
    /// préférence : c'est idempotent, ça ne dépend d'aucun ordre de migration,
    /// et ça vaut pour tout déplacement futur du dossier.
    ///
    /// - Returns: le chemin d'origine s'il est encore valide, le fichier de
    ///   même nom dans `avatarsDirectory` sinon, et à défaut le chemin
    ///   d'origine — inventer vaudrait moins que laisser l'appelant afficher
    ///   son repli.
    public static func resolvedImagePath(_ iconPath: String,
                                         avatarsDirectory: URL?,
                                         fileManager: FileManager = .default) -> String {
        guard prefersCustomIcon(iconPath) else { return iconPath }
        guard !fileManager.fileExists(atPath: iconPath) else { return iconPath }
        guard let directory = avatarsDirectory else { return iconPath }
        let candidate = directory
            .appendingPathComponent((iconPath as NSString).lastPathComponent)
        return fileManager.fileExists(atPath: candidate.path) ? candidate.path : iconPath
    }
}

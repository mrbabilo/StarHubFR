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

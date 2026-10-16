import Foundation

/// R9 (audit UX 2026-10-16) — le geste qui satisfait une dépendance requise,
/// là où le manque s'affiche : l'encart de la ligne et l'onglet Dépendances.
/// Avant, l'encart n'offrait qu'une recherche Nexus pour une dépendance
/// manquante, et rien du tout pour une dépendance en pause.
enum DependencyFix: Equatable {
    /// Installée mais en pause : l'activer (par les gardes de l'interrupteur).
    case activate(ModItem)
    /// Manquante, page Nexus connue, téléchargement direct permis (Premium).
    case install(nexusId: Int)
    /// Manquante, page connue, sans Premium : l'onglet Fichiers.
    case openPage(nexusId: Int)
    /// Manquante, page inconnue (hors du dump Pathoschild) : la recherche.
    case search

    /// `nil` quand rien n'est à faire : une copie active satisfait déjà la
    /// dépendance, même si une autre dort en pause.
    ///
    /// - Parameters:
    ///   - installed: le parc à plat (`flattenedMods`), pauses comprises.
    ///   - nexusId: la page connue de l'annuaire de dépendances.
    ///   - directDownload: `false` seulement pour un compte connu non Premium.
    static func action(for uniqueId: String, installed: [ModItem],
                       nexusId: Int?, directDownload: Bool) -> DependencyFix? {
        let key = uniqueId.lowercased()
        let copies = installed.filter { $0.uniqueId.lowercased() == key }
        if copies.contains(where: \.isEnabled) { return nil }
        if let paused = copies.first { return .activate(paused) }
        guard let nexusId else { return .search }
        return directDownload ? .install(nexusId: nexusId) : .openPage(nexusId: nexusId)
    }
}

import Foundation

/// Les natures de problème derrière le cadrage « Problèmes » de la liste
/// (audit UX 2026-10-02, 2ᵉ passe) : des **puces de filtre**, pas des
/// sections. Un mod qui cumule deux natures reste une ligne ; une
/// catégorisation par sections le dupliquerait et briserait le compte du
/// segment.
///
/// Même définition que `ModListScoping.scoped(.issues)` : l'anomalie
/// (`ModAnomalyReport`, pastille de ligne) plus l'état de la page Nexus. Le
/// filtre par nature se pose **après** ce cadrage — il réduit la liste
/// déjà cadrée, il ne la recalcule pas.
public enum ModProblemKind: String, CaseIterable, Sendable, Hashable {
    /// Erreurs du journal SMAPI sur la version installée.
    case errors
    /// Avertissements du journal sur la version installée.
    case warnings
    /// Dépendance requise absente, ou en pause sous un mod actif.
    case dependencies
    /// Manifeste sans `UniqueID` : SMAPI ne chargera pas le mod.
    case unloadable
    /// Installé plusieurs fois (copie active ou dormante).
    case duplicates
    /// Ancienne ou nouvelle copie d'un mod dont l'auteur a changé l'identifiant.
    case renamed
    /// Verdict de compatibilité smapi.io (cassé, abandonné…).
    case compatibility
    /// Page Nexus indisponible ou retirée.
    case nexus

    public var l10nKey: String {
        switch self {
        case .errors:        return L10nKeys.problemErrors
        case .warnings:      return L10nKeys.problemWarnings
        case .dependencies:  return L10nKeys.problemDependencies
        case .unloadable:    return L10nKeys.problemUnloadable
        case .duplicates:    return L10nKeys.problemDuplicates
        case .renamed:       return L10nKeys.problemRenamed
        case .compatibility: return L10nKeys.problemCompatibility
        case .nexus:         return L10nKeys.problemNexus
        }
    }

    /// Clés de libellé posées ici : Core ne référence pas `L10n.swift`
    /// (app), et l'app n'a pas à répéter la table.
    enum L10nKeys {
        static let problemErrors        = "mods_problem_errors"
        static let problemWarnings      = "mods_problem_warnings"
        static let problemDependencies  = "mods_problem_dependencies"
        static let problemUnloadable    = "mods_problem_unloadable"
        static let problemDuplicates    = "mods_problem_duplicates"
        static let problemRenamed       = "mods_problem_renamed"
        static let problemCompatibility = "mods_problem_compatibility"
        static let problemNexus         = "mods_problem_nexus"
    }
}

public enum ModProblemKinds {
    /// Les natures portées par un mod du cadrage : l'anomalie de sa ligne
    /// (composants d'un pack compris, règle de `ModAnomalyReport`) plus
    /// l'état Nexus du premier composant qui en porte un.
    public static func of(anomaly: ModAnomaly?, hasNexusState: Bool) -> Set<ModProblemKind> {
        var kinds: Set<ModProblemKind> = []
        if let a = anomaly {
            if a.errorCount > 0 { kinds.insert(.errors) }
            if a.warningCount > 0 { kinds.insert(.warnings) }
            if a.hasDependencyIssue { kinds.insert(.dependencies) }
            if a.isUnloadable { kinds.insert(.unloadable) }
            if a.duplicate != nil { kinds.insert(.duplicates) }
            if a.renamed != nil { kinds.insert(.renamed) }
            if a.compatibility != nil { kinds.insert(.compatibility) }
        }
        if hasNexusState { kinds.insert(.nexus) }
        return kinds
    }
}

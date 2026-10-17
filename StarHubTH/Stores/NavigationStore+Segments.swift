import Foundation

// Les segments des pages à onglets, sortis de `NavigationStore.swift`
// (plafond de 400 lignes) pour y loger le canal d'aperçu de profil (N-12).

/// Les trois onglets de la page « Alertes système ».
enum AlertsSegment: CaseIterable, Sendable {
    case alerts, keybinds, conflicts
}

/// Les trois segments de la page « Sauvegardes des mods » (I-T8).
enum BackupsSegment: CaseIterable, Sendable {
    case install, config, files
}

/// Les onglets de « Diagnostic & Performances » (D4-T4 §3a). « Performances »
/// arrive avec l'avant / après (plan 4) : pas d'onglet vide avant.
enum DiagnosticsSegment: CaseIterable, Sendable {
    case health, journal, performance
}

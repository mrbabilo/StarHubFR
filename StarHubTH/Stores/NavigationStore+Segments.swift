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

/// R6 — les trois segments de la page d'une partie.
enum SaveSegment: CaseIterable, Sendable {
    case details, mods, history
}

extension NavigationStore {
    /// Ouvre une partie sur un segment : « Modifier », « Historique… » ou
    /// « Mods de cette partie » du menu d'actions.
    func openSave(_ save: SaveGameInfo, segment: SaveSegment) {
        setEditingSave(save)
        saveSegment = segment
    }

    /// N-08 — ↩ sur une partie dans la palette : sa page, sur Détails.
    func requestSave(folderName: String) {
        pendingSaveFocus = folderName
        requestTab(.saves)
    }

    /// Consommé sur l'onglet des parties : par `MainView` à l'arrivée, après
    /// la remise à zéro du changement d'onglet (poser `editingSave` avant
    /// serait effacé), par `SavesTab` si l'on y est déjà. Une partie disparue
    /// n'ouvre rien ; la demande tombe dans tous les cas.
    func consumeSaveFocus(in saves: [SaveGameInfo]) {
        guard let folderName = pendingSaveFocus else { return }
        pendingSaveFocus = nil
        if let save = saves.first(where: { $0.folderName == folderName }) {
            openSave(save, segment: .details)
        }
    }
}

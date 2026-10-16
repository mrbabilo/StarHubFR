import Foundation

/// L'historique de navigation entre les pages, et ce que fait « Retour ».
///
/// **Pourquoi un type pur.** L'historique vivait en quatre `@State` de
/// `MainView` (piles, drapeau « ouvert par un saut », drapeau de
/// retour/avancer) : hors de portée d'un test, du menu « Aller » et du ✕ de
/// la fiche. Le ✕ fermait la fiche sans rien savoir du saut qui l'avait
/// ouverte : après « Voir le mod » depuis les Alertes, il laissait sur la
/// liste des mods au lieu de ramener aux Alertes (audit UX 2026-10-16, N-00).
/// La vue applique maintenant ce que ce type décide.
public struct NavigationHistory: Equatable, Sendable {

    /// Le détail ouvert au moment du retour, du plus haut au plus bas.
    public enum OpenDetail: Equatable, Sendable {
        case none
        case saveEditor
        case saveTimeline
        /// L'éditeur de config, avec ou sans fiche dessous.
        case modConfig(detailUnderneath: Bool)
        case modDetail
    }

    /// Ce que la vue doit faire : fermer un détail, changer de page, ou les deux.
    public struct BackStep: Equatable, Sendable {
        public let close: OpenDetail
        public let goTo: SidebarDestination?
    }

    public private(set) var backStack: [SidebarDestination] = [.home]
    public private(set) var forwardStack: [SidebarDestination] = []
    /// Fiche ou config ouverte par un saut d'une autre page : le retour y ramène.
    public var detailOpenedByJump = false

    public init() {}

    /// Une page vient d'être affichée. Après Retour ou Avancer, elle est déjà
    /// en haut de la pile : rien n'est empilé, l'avant reste. (L'ancien
    /// drapeau « retour en cours » de `MainView` ne changeait donc rien.)
    public mutating func didEnter(_ destination: SidebarDestination) {
        guard backStack.last != destination else { return }
        backStack.append(destination)
        forwardStack.removeAll()
    }

    public func canGoBack(from open: OpenDetail) -> Bool {
        open != .none || backStack.count > 1
    }

    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// « Retour » : ferme le détail du dessus ; si ce détail venait d'un saut,
    /// ramène aussi à la page d'où il a été ouvert.
    public mutating func back(from open: OpenDetail) -> BackStep {
        switch open {
        case .saveEditor, .saveTimeline:
            return BackStep(close: open, goTo: nil)
        case .modConfig(let detailUnderneath):
            return BackStep(close: open,
                            goTo: detailOpenedByJump && !detailUnderneath ? previousPage() : nil)
        case .modDetail:
            return BackStep(close: open, goTo: detailOpenedByJump ? previousPage() : nil)
        case .none:
            return BackStep(close: .none, goTo: previousPage())
        }
    }

    /// « Avancer » : la page quittée par le dernier retour, s'il y en a une.
    public mutating func forward() -> SidebarDestination? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(next)
        return next
    }

    private mutating func previousPage() -> SidebarDestination? {
        detailOpenedByJump = false
        guard backStack.count > 1 else { return nil }
        forwardStack.append(backStack.removeLast())
        return backStack.last ?? .home
    }
}

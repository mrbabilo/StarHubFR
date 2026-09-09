import SwiftUI

/// ⌘F donne le focus au champ de recherche de l'écran courant.
///
/// **Pourquoi un raccourci local et pas une entrée de menu.** Un menu vit dans
/// la scène App et ne peut écrire aucun `@FocusState` de vue ; il faudrait un
/// canal, et ce canal resterait **armé** sur les écrans sans recherche —
/// l'Accueil, les Réglages — pour se déclencher au prochain écran qui en a un.
/// C'est la famille de bugs de `releaseCheckInFlight`. Un raccourci local
/// n'existe qu'où le champ existe : ⌘F ne fait rien ailleurs, sans état à
/// nettoyer.
///
/// ⚠️ **Un seul liage par raccourci.** ⌘K a été lié deux fois le 2026-09-09
/// (menu + bouton local) : le menu gagne au niveau app et le local ne partait
/// jamais. Ne pas doubler celui-ci d'une entrée de menu sans retirer ceci.
///
/// Le prix assumé : ⌘F ne s'affiche nulle part. ⌘F étant universel, la
/// découvrabilité ne le justifiait pas — contrairement à ⌘K.
struct SearchFieldShortcut: ViewModifier {
    let focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .focused(focus)
            .background(
                // Bouton invisible : `background` ne participe pas au calcul
                // de taille, le champ garde sa géométrie.
                Button("") { focus.wrappedValue = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            )
    }
}

extension View {
    /// Porte le focus **et** son raccourci : un seul appel par champ, pour que
    /// les deux ne puissent pas se désynchroniser d'un écran à l'autre.
    func searchFieldShortcut(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(SearchFieldShortcut(focus: focus))
    }
}

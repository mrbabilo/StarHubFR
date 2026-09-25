import AppKit
import SwiftUI

/// Les réglages d'accessibilité du système, lus là où l'app anime ou
/// atténue (I-T4). Lus à chaque appel sur `NSWorkspace` : un réglage changé
/// pendant que l'app tourne vaut dès le prochain rendu.
///
/// « Réduire la transparence » n'a rien à faire ici : les trois matériaux
/// de l'app sont des matériaux système, qui deviennent opaques d'eux-mêmes.
enum Motion {
    static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// L'animation demandée, ou aucune quand l'utilisateur a choisi
    /// « Réduire les animations » : l'état change d'un coup, défilements et
    /// ressorts compris. Toute animation de l'app passe par ici.
    static func animation(_ animation: Animation = .default) -> Animation? {
        isReduced ? nil : animation
    }
}

/// `withAnimation`, qui s'abstient sous « Réduire les animations ».
func withMotion<Result>(_ animation: Animation = .default,
                        _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(animation), body)
}

extension AppDesign.Color {
    /// Un gris secondaire atténué — sauf sous « Augmenter le contraste », où
    /// il revient au secondaire plein : l'atténuation est justement ce que
    /// ce réglage demande de retirer.
    static func dimmedSecondary(_ opacity: Double) -> SwiftUI.Color {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? .secondary : SwiftUI.Color.secondary.opacity(opacity)
    }
}

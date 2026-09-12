import Foundation
import Observation

/// L'état de l'alerte globale de l'application : le message affiché et la
/// présentation.
///
/// Un seul producteur côté ViewModel (`showModal`) ; les vues ne posent jamais
/// `shown` à `true` à la main — SwiftUI repose le binding à `false` quand
/// l'utilisateur ferme l'alerte. Extrait du ViewModel (P8, famille « alertes »,
/// 2026-09-12) : l'état ne décide de rien, il porte deux champs et une
/// transition.
@Observable
final class AlertStore {
    /// Le message affiché. Posé par `show(_:)` ; rester après la fermeture est
    /// sans effet tant que `shown` est `false`.
    private(set) var message = ""
    /// `true` présente l'alerte ; le binding de la vue l'éteint à la fermeture.
    var shown = false

    func show(_ message: String) {
        self.message = message
        shown = true
    }
}

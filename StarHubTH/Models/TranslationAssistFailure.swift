import Foundation

/// N-11 (audit UX 2026-10-16) — un refus de l'aide à la traduction de
/// l'éditeur, son message, et le réglage qui en lève la cause s'il y en a un.
///
/// Avant, le message disait « dans Réglages › Traduction assistée » sans y
/// mener. Le quota épuisé et le rythme refusé n'ont pas de réglage : ils se
/// règlent chez DeepL ou en attendant, un bouton vers les Réglages y ferait
/// chercher une cause qui n'y est pas.
enum TranslationAssistFailure: Equatable {
    /// Le secours en ligne s'est arrêté (quota, rythme, clé refusée).
    case stopped(TranslationBatchRun.Report.FallbackStop)
    /// Traduire une sélection passe par DeepL, et aucune clé n'est réglée.
    case noFallback
    /// Ni IA locale ni DeepL : rien ne peut pré-traduire.
    case noEngine

    var messageKey: String {
        switch self {
        case .stopped(.quotaExhausted): L10n.Mods.translationEditorQuota
        case .stopped(.rateLimited): L10n.Mods.translationEditorRateLimited
        case .stopped(.unauthorized): L10n.Mods.translationEditorUnauthorized
        case .noFallback: L10n.Mods.translationEditorSelectionNoFallback
        case .noEngine: L10n.Mods.translationEditorPretranslateNoAI
        }
    }

    /// La section « Traduction assistée » porte l'IA locale **et** la clé
    /// DeepL (`SettingsSection.translationAI`).
    var settings: SettingsSection? {
        switch self {
        case .stopped(.quotaExhausted), .stopped(.rateLimited): nil
        case .stopped(.unauthorized), .noFallback, .noEngine: .translationAI
        }
    }
}

/// Ce que la zone d'échec de l'éditeur affiche : le texte, et le réglage qui
/// y remédie. Un seul état, pour que le bouton ne survive jamais au message.
struct TranslationEditorNotice: Equatable {
    let text: String
    var settings: SettingsSection?
}

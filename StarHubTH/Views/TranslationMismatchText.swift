import Foundation

/// Le libellé d'une marque manquante dans l'écran de blocage. Les marques
/// ordinaires s'affichent telles quelles (`#$b#`) ; la structure d'une réponse
/// rapide `$y` n'a pas de forme lisible, elle s'explique — avec la correction
/// la plus fréquente, l'apostrophe typographique (Sterling `winter_Mon6`).
enum TranslationMismatchText {
    static func label(_ mismatch: TranslationTokenCheck.Mismatch, _ localization: LocalizationStore) -> String {
        if mismatch.token == TranslationTokenCheck.bareHashToken {
            return localization.L(L10n.Mods.translationBareHash)
        }
        guard mismatch.token == TranslationTokenCheck.quickResponseToken else { return mismatch.token }
        return String(format: localization.L(L10n.Mods.translationQuickResponse),
                      Int64(mismatch.expected), Int64(mismatch.found))
    }
}

extension L10n.Mods {
    static let translationQuickResponse = "mods_translation_quick_response"
    static let translationEditorWarnings = "mods_translation_editor_warnings"
    static let translationEditorWarningsHint = "mods_translation_editor_warnings_hint"
    static let translationBareHash = "mods_translation_bare_hash"
}

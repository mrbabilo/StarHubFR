import Foundation

/// Les libellés des écarts de marques, partagés par l'éditeur (blocage, note
/// d'avertissement) et le refus d'un lot. Chaque écart dit son **sens** :
/// la faute la plus fréquente du parc ajoute une marque (`!#$h` pour `!$h`,
/// 94 lignes) — la dire « manquante » contredisait le texte même du
/// traducteur, qui la contient.
enum TranslationMismatchText {
    /// Le nom d'une marque. Les marques ordinaires s'affichent telles quelles
    /// (`#$b#`) ; le `#` nu dit ce qu'il fait. La structure `$y _` n'a de forme
    /// lisible qu'avec ses comptes (`label`) : sans eux, elle reste brute.
    static func name(_ token: String, _ localization: LocalizationStore) -> String {
        token == TranslationTokenCheck.bareHashToken ? localization.L(L10n.Mods.translationBareHash) : token
    }

    /// Une réponse rapide `$y` s'explique — avec la correction la plus
    /// fréquente, l'apostrophe typographique (Sterling `winter_Mon6`).
    static func label(_ mismatch: TranslationTokenCheck.Mismatch, _ localization: LocalizationStore) -> String {
        guard mismatch.token == TranslationTokenCheck.quickResponseToken else {
            return name(mismatch.token, localization)
        }
        return String(format: localization.L(L10n.Mods.translationQuickResponse),
                      Int64(mismatch.expected), Int64(mismatch.found))
    }

    /// Les écarts groupés par sens — « marque(s) manquante(s) : … », puis
    /// « marque(s) en trop : … » —, la réponse rapide à part : son libellé
    /// porte déjà ses deux comptes.
    static func grouped(_ mismatches: [TranslationTokenCheck.Mismatch], _ localization: LocalizationStore) -> String {
        let quick = mismatches.filter { $0.token == TranslationTokenCheck.quickResponseToken }
        let marks = mismatches.filter { $0.token != TranslationTokenCheck.quickResponseToken }
        let missing = marks.filter { $0.found < $0.expected }.map(\.token)
        let extra = marks.filter { $0.found > $0.expected }.map(\.token)
        var parts: [String] = []
        if !missing.isEmpty { parts.append(listed(missing, L10n.Mods.translationLotReasonMissingMarkers, localization)) }
        if !extra.isEmpty { parts.append(listed(extra, L10n.Mods.translationLotReasonExtraMarkers, localization)) }
        parts += quick.map { label($0, localization) }
        return parts.joined(separator: "  ")
    }

    /// `markers` sous l'intitulé `key` (« marque(s) en trop : %@ »).
    static func listed(_ markers: [String], _ key: String, _ localization: LocalizationStore) -> String {
        String(format: localization.L(key), markers.map { name($0, localization) }.joined(separator: ", "))
    }

    /// Le texte du blocage : les écarts bloquants, puis — à la ligne — ceux
    /// qui ne font qu'avertir. Les taire cachait la contrepartie de la faute :
    /// le `$h` perdu quand `#$h` a été ajouté, le `#$b#` remplacé par `##`.
    /// Recalculé sur `draft` : l'éditeur efface le blocage dès qu'il change.
    static func blocked(_ blocked: [TranslationTokenCheck.Mismatch], english: String, draft: String,
                        _ localization: LocalizationStore) -> String {
        var text = String(format: localization.L(L10n.Mods.translationEditorBlocked), Int64(blocked.count))
            + "  " + grouped(blocked, localization)
        let soft = TranslationTokenCheck.mismatches(source: english, target: draft).filter { !$0.isHard }
        if !soft.isEmpty {
            text += "\n" + localization.L(L10n.Mods.translationEditorWarnings) + "  " + grouped(soft, localization)
        }
        return text
    }
}

extension L10n.Mods {
    static let translationQuickResponse = "mods_translation_quick_response"
    static let translationEditorWarnings = "mods_translation_editor_warnings"
    static let translationEditorWarningsHint = "mods_translation_editor_warnings_hint"
    static let translationBareHash = "mods_translation_bare_hash"
}

import SwiftUI

/// Les écarts de marques qui ne cassent pas le jeu (spec C3-T9 §4) : montrés
/// pendant la saisie, sous le champ, sans bloquer l'enregistrement. L'éditeur
/// se ferme après un enregistrement réussi — une note « après coup » ne serait
/// jamais lue.
struct TranslationWarningNote: View {
    let english: String
    let draft: String
    @ObservedObject var localization: LocalizationStore

    private var warnings: [TranslationTokenCheck.Mismatch] {
        guard !draft.isEmpty else { return [] }
        return TranslationTokenCheck.mismatches(source: english, target: draft).filter { !$0.isHard }
    }

    var body: some View {
        let shown = warnings
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(localization.L(L10n.Mods.translationEditorWarnings) + "  "
                     + TranslationMismatchText.grouped(shown, localization))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                Text(localization.L(L10n.Mods.translationEditorWarningsHint))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
            }
        }
    }
}

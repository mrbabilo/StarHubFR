import SwiftUI

/// L'engrenage d'une ligne du rapport de raccourcis — partagé par les
/// groupes de problèmes et la vue « tous les raccourcis » (C4-T13). Le geste
/// arrive tout fait (`action`) : `KeybindReportSection.openConfig` le compose,
/// bascule d'onglet comprise. Glyphe seul, donc cible de 18×18 avec
/// `contentShape` : un glyph de 11 pt est plus petit que le curseur immobile
/// qu'exige macOS pour une infobulle, défaut déjà payé dans la liste (note du
/// glyph `note.text` dans `ModListView`).
///
/// `.layoutPriority(1)` sur un cadre déjà fixe à 18×18 : en fenêtre étroite
/// c'est le texte de la ligne qui tronque (son `lineLimit` + `truncationMode`
/// restent maîtres), jamais le bouton qui rétrécit.
struct KeybindConfigButton: View {
    @ObservedObject var localization: LocalizationStore
    let action: () -> Void

    var body: some View {
        // Évaluée une fois par ligne (ronde finale) : elle servait à la fois
        // à `.help` et à `.accessibilityLabel`.
        let settingsLabel = localization.L(L10n.Settings.configModSettings)
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .help(settingsLabel)
        .accessibilityLabel(settingsLabel)
        .accessibilityHint(localization.L(L10n.Settings.configModSettingsA11yHint))
        .layoutPriority(1)
    }
}

import SwiftUI

/// Réglages › Affichage : la taille du texte (I-T4), trois crans.
struct TextScaleSettingsSection: View {
    @ObservedObject var localization: LocalizationStore
    @AppStorage(TextScale.defaultsKey) private var textScale = TextScale.normal.rawValue

    var body: some View {
        StandardSection(title: localization.L(L10n.Settings.display),
                        footer: localization.L(L10n.Settings.footerDisplay)) {
            HStack {
                Text(localization.L(L10n.Settings.textSize))
                    .font(AppDesign.Font.body)
                Spacer()
                Picker(localization.L(L10n.Settings.textSize), selection: $textScale) {
                    ForEach(TextScale.allCases, id: \.self) { scale in
                        Text(localization.L(label(scale))).tag(scale.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private func label(_ scale: TextScale) -> String {
        switch scale {
        case .normal: return L10n.Settings.textSizeNormal
        case .large: return L10n.Settings.textSizeLarge
        case .extraLarge: return L10n.Settings.textSizeExtraLarge
        }
    }
}

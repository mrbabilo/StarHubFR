import SwiftUI

/// L'aide des raccourcis clavier : une feuille, ouverte par l'icône clavier
/// du pied de la barre latérale ou par ⌘/ (menu Aide).
///
/// Tout vient de `KeyboardShortcutCatalog` (Core) : la vue ne décide d'aucun
/// raccourci, elle les dessine — touches en pastilles, action à côté.
struct ShortcutsHelpView: View {
    @ObservedObject var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: AppDesign.Spacing.sm) {
                    IconTile(icon: "keyboard", tint: .gray, size: 28)
                    Text(localization.L(L10n.Shortcuts.title))
                        .font(AppDesign.Font.headline(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Button(localization.L(L10n.Main.close)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(AppDesign.Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                    ForEach(KeyboardShortcutCatalog.groups()) { group in
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                            Label(localization.L(group.titleKey), systemImage: Self.icon(for: group.titleKey))
                                .font(AppDesign.Font.caption(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .accessibilityAddTraits(.isHeader)
                            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                                ForEach(group.entries) { entry in
                                    row(entry)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                        }
                    }
                }
                .padding(AppDesign.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 480, height: 560)
    }

    private func row(_ entry: ShortcutEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.md) {
            HStack(spacing: 3) {
                ForEach(Array(entry.keys.enumerated()), id: \.offset) { _, key in
                    if key == ShortcutEntry.or {
                        Text("/").font(AppDesign.Font.caption).foregroundStyle(.secondary)
                    } else {
                        keycap(key)
                    }
                }
            }
            .frame(width: 110, alignment: .leading)
            Text(localization.L(entry.labelKey))
                .font(AppDesign.Font.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        // VoiceOver lit l'action puis les touches, pas une suite de glyphes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localization.L(entry.labelKey))
        .accessibilityValue(entry.keys.filter { $0 != ShortcutEntry.or }.joined(separator: " "))
    }

    /// Une touche en relief : face claire, tranche plus sombre dessous.
    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(AppDesign.Font.caption(.medium).monospaced())
            .frame(minWidth: 20)
            .padding(.horizontal, AppDesign.Spacing.xs)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(AppDesign.Color.controlBg))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(AppDesign.Opacity.strong), lineWidth: 0.5))
            .shadow(color: .black.opacity(AppDesign.Opacity.strong), radius: 0, y: 1)
    }

    /// Le glyphe d'un groupe de raccourcis.
    private static func icon(for titleKey: String) -> String {
        switch titleKey {
        case L10n.Shortcuts.groupScreens:    return "sidebar.left"
        case L10n.Shortcuts.groupNavigation: return "arrow.triangle.turn.up.right.diamond"
        case L10n.Shortcuts.groupModList:    return "list.bullet"
        case L10n.Shortcuts.groupPalette:    return "command"
        case L10n.Shortcuts.groupDialogs:    return "macwindow"
        default:                             return "app"
        }
    }
}

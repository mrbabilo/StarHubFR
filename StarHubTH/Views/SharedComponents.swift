import SwiftUI

// MARK: - Initials Avatar
/// Circular "initials" badge — was reimplemented as the same
/// `ZStack { Circle().fill(...); Text(...) }` at 5 separate call sites
/// (the account-menu profile indicator, out-of-date/update mod rows, and
/// both mod-profile avatars); this is the one shared implementation.
struct InitialsAvatar: View {
    let text: String
    var initialsCount: Int = 1
    var size: CGFloat
    var fillColor: Color = .accentColor
    var textColor: Color = .white
    var fontSize: CGFloat
    var fontWeight: Font.Weight = .bold
    /// Optional border ring, e.g. to separate a small badge from the
    /// image it's overlaid on.
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 2

    private var initials: String {
        String(text.prefix(initialsCount)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .overlay {
                    if let strokeColor {
                        Circle().stroke(strokeColor, lineWidth: strokeWidth)
                    }
                }
            Text(initials)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(textColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Standard Section
struct StandardSection<Content: View>: View {
    let title: String
    let footer: String?
    /// Glyphe en tuile devant le titre, à la manière des Réglages Système ;
    /// la section devient alors une carte en relief (`cardSurface`).
    let icon: (name: String, tint: Color)?
    let content: Content

    init(title: String, icon: (name: String, tint: Color)? = nil, footer: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            if !title.isEmpty {
                HStack(spacing: AppDesign.Spacing.sm) {
                    if let icon { IconTile(icon: icon.name, tint: icon.tint, size: 22) }
                    Text(verbatim: title)
                        .font(AppDesign.Font.body(.bold))
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader) // rotor VoiceOver : navigation par titres (I-T3)
                }
            }

            if icon != nil {
                VStack(spacing: 0) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(padding: AppDesign.Spacing.lg)
            } else {
                VStack(spacing: 0) {
                    content
                }
                .padding(AppDesign.Spacing.lg)
                .background(Color.clear)
                .cornerRadius(AppDesign.Radius.section)
                .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.section).stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 1))
            }

            if let footerText = footer, !footerText.isEmpty {
                Text(verbatim: footerText)
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .padding(.horizontal, AppDesign.Spacing.xs)
                    .padding(.top, AppDesign.Spacing.xs)
                    .tint(.accentColor)
            }
        }
    }
}

// MARK: - Standard Row
struct StandardRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let showDivider: Bool

    init(title: LocalizedStringKey, detail: LocalizedStringKey, showDivider: Bool = true) {
        self.title = title
        self.detail = detail
        self.showDivider = showDivider
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(AppDesign.Font.body)
                    .foregroundColor(.primary)
                Spacer()
                Text(detail)
                    .font(AppDesign.Font.body)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)

            if showDivider {
                Divider()
            }
        }
    }
}

// MARK: - Info Popover Button
struct InfoPopoverButton: View {
    let text: String
    var color: Color = .secondary
    @State private var showPopover = false

    var body: some View {
        Button(action: {
            showPopover.toggle()
        }) {
            Image(systemName: "info.circle")
                .foregroundColor(color)
                .font(AppDesign.Font.caption)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            Text(verbatim: text)
                .font(AppDesign.Font.caption)
                .padding()
                .frame(width: 200)
        }
    }
}

// MARK: - Shared Formatters
/// Les octets, tels que toute l'app les écrit — `ByteCountFormatter`,
/// style `.file`. Portait quatre copies identiques dans trois fichiers
/// (passe de simplification 2026-10-03).
enum SharedFormatters {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// Paire étiquette/valeur empilée — deux copies identiques
/// (`ProfileConfigCompareView`, `TranslationRecoveryDiffView`).
func labelledValue(_ label: String, _ value: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label)
            .font(AppDesign.Font.iconXXS(.semibold))
            .foregroundColor(.secondary)
        Text(value)
            .font(AppDesign.Font.caption)
            .foregroundColor(color)
            .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// Rangée d'état « glyphe + texte » — deux copies identiques
/// (`KeybindReportSection`, `ModConflictSection`).
func statusRow(icon: String, color: Color, text: String) -> some View {
    HStack(spacing: AppDesign.Spacing.sm) {
        Image(systemName: icon).foregroundColor(color)
        Text(text).foregroundColor(.secondary)
    }
}

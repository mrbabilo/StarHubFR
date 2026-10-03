import SwiftUI

/// Les puces de type de problème du cadrage « Problèmes » (audit UX
/// 2026-10-02, 2ᵉ passe) : un filtre par nature, pas des sections — un mod
/// qui cumule deux natures reste une ligne. Une seule puce active ; un
/// second clic rend toute la liste.
struct ProblemKindChips: View {
    let counts: [(kind: ModProblemKind, count: Int)]
    @Binding var selection: ModProblemKind?
    let L: (String) -> String

    var body: some View {
        WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.xs) {
            ForEach(counts, id: \.kind) { chip in
                chipView(chip)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L(L10n.Mods.problemChipsTitle))
    }

    private func chipView(_ chip: (kind: ModProblemKind, count: Int)) -> some View {
        let isSelected = selection == chip.kind
        return Button {
            withMotion(.snappy) { selection = isSelected ? nil : chip.kind }
        } label: {
            HStack(spacing: AppDesign.Spacing.xs) {
                Image(systemName: Self.icon(for: chip.kind))
                    .foregroundStyle(Self.tint(for: chip.kind))
                Text(L(chip.kind.l10nKey))
                Text("\(chip.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(AppDesign.Font.caption)
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.vertical, 3)
            .background(isSelected ? Self.tint(for: chip.kind).opacity(AppDesign.Opacity.medium)
                                   : Color.primary.opacity(AppDesign.Opacity.light),
                        in: Capsule())
            .overlay(Capsule().stroke(Self.tint(for: chip.kind),
                                      lineWidth: isSelected ? 1.5 : 0))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(L(L10n.Mods.problemFilterHint))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Glyphe par nature : la couleur est doublée d'une forme.
    static func icon(for kind: ModProblemKind) -> String {
        switch kind {
        case .errors:        return "xmark.octagon.fill"
        case .warnings:      return "exclamationmark.triangle.fill"
        case .dependencies:  return "link.circle.fill"
        case .unloadable:    return "doc.questionmark.fill"
        case .duplicates:    return "square.on.square"
        case .renamed:       return "arrow.triangle.2.circlepath"
        case .compatibility: return "wrench.and.screwdriver.fill"
        case .nexus:         return "arrowshape.zigzag.right.fill"
        }
    }

    static func tint(for kind: ModProblemKind) -> Color {
        switch kind {
        case .errors:        return AppDesign.Color.error
        case .warnings:      return AppDesign.Color.warning
        case .dependencies:  return AppDesign.Color.accent
        case .unloadable:    return AppDesign.Color.paused
        case .duplicates:    return AppDesign.Color.quarantine
        case .renamed:       return AppDesign.Color.quarantine
        case .compatibility: return AppDesign.Color.info
        case .nexus:         return .secondary
        }
    }
}

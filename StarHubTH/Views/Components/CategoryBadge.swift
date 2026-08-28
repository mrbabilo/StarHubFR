import SwiftUI

// MARK: - Category Badge

/// Compact colored pill shown next to a mod's author/version. The dot uses the
/// category's curated color and the text uses the localized name, so the row
/// is scannable by hue even at a glance.
///
/// Déménagé de `ModListView.swift` au châssis du design system (H-T1) : deux
/// vues le consomment déjà, il n'appartenait plus à la liste des mods.
///
/// Les valeurs littérales (7, 6, 2, 4, 0.12, 0.30, 0.5, police 10) sont
/// conservées telles quelles : aucun token ne les porte, et le token voisin
/// changerait l'apparence — ce que la phase 0 s'interdit.
struct CategoryBadge: View {
    let category: NexusCategory
    let L: (String) -> String

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Circle()
                .fill(category.color)
                .frame(width: 7, height: 7)
            Text(category.localizedName(L))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(category.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(category.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(category.color.opacity(0.30), lineWidth: 0.5)
        )
        .help(category.englishName)
    }
}

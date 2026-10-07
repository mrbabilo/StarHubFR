import SwiftUI

extension ModConflictSection {
    /// A5-T4 — deux `Load` exclusifs sur la même cible : Content Patcher
    /// n'applique **ni l'un ni l'autre**. Dormante si un côté est en pause.
    func predictedRow(_ pair: ModConflictPair) -> some View {
        let active = Set(installedMods.filter(\.isEnabled).map(\.folderName))
        let dormant = !(active.contains(pair.first) && active.contains(pair.second))
        let assets = ContentPatcherLoadTargets.assets(activating: [pair.first], other: pair.second,
                                                      in: vm.contentPatcherLoadIndex.pairs)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Text("· \(displayName(pair.first)) × \(displayName(pair.second))")
                    .font(AppDesign.Font.body(.medium))
                    .lineLimit(1).truncationMode(.middle)
                badge(localization.L(dormant ? L10n.Conflicts.predictedDormant : L10n.Conflicts.predictedBadge))
                Spacer(minLength: AppDesign.Spacing.sm)
                dismissButton(for: pair)
            }
            Text(String(format: localization.L(L10n.Conflicts.predictedDetail), assets.joined(separator: ", ")))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

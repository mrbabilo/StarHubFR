import SwiftUI

// EmptyStateDropZone.swift
// Zone de drop XXL affichée quand la liste de mods est vide (première
// utilisation). Remplace le simple message textuel par une zone visuelle
// qui invite explicitement au drag-and-drop de fichiers .zip.
//
// Intégré dans ModListView.swift dans la branche `if vm.mods.isEmpty`.

struct EmptyStateDropZone: View {
    @ObservedObject var vm: StarHubTHViewModel
    let onInstall: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onInstall) {
            VStack(spacing: AppDesign.Spacing.xl) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 48))
                    .foregroundColor(AppDesign.Color.accent)

                VStack(spacing: AppDesign.Spacing.xs) {
                    Text(vm.L(L10n.ModInstall.emptyTitle))
                        .font(AppDesign.Font.headline)
                        .foregroundColor(.primary)
                    Text(vm.L(L10n.ModInstall.emptyHint))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppDesign.Spacing.xxl)
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.lg)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .foregroundColor(AppDesign.Color.accent.opacity(isHovered ? AppDesign.Opacity.medium : AppDesign.Opacity.light))
            )
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.lg)
                    .foregroundColor(AppDesign.Color.accent.opacity(isHovered ? AppDesign.Opacity.subtle : 0))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(vm.L(L10n.ModInstall.emptyTitle))
        .accessibilityHint(vm.L(L10n.ModInstall.emptyHint))
        .onHover { isHovered = $0 }
        .pointingHandCursor()
    }
}

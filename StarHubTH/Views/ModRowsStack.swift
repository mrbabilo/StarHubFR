import SwiftUI

/// Les lignes d'une section de la liste des mods — partagées par la section
/// unique (`ModSectionGroup`) et les sections des groupes (I-T21).
struct ModRowsStack: View {
    let mods: [ModItem]
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var listState: ModListState

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(mods.enumerated()), id: \.element.id) { idx, mod in
                if mod.isGroup, let children = mod.children {
                    ModGroupRow(mod: mod, children: children, vm: viewModel, localization: localization, listState: listState)
                } else {
                    ModListRow(mod: mod, vm: viewModel, localization: localization, listState: listState,
                               isChild: false, isGroupHeader: false, isExpanded: .constant(false))
                        .contentShape(Rectangle())
                        .onTapGesture { listState.clickRow(mod.folderName, viewModel: viewModel) }
                }
                if idx < mods.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(AppDesign.Opacity.subtle))
                        .frame(height: 1)
                        .padding(.leading, 48)
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, -8)
    }
}

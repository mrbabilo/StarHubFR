import SwiftUI

/// I-T21 lot 2 — « Ranger dans ▸ » (ligne, barre de sélection), le menu du
/// bandeau d'une section et la feuille du nom d'un groupe.
struct ModGroupMoveMenu: View {
    let folders: [String]
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var listState: ModListState

    var body: some View {
        Menu {
            ForEach(viewModel.groups.state.groups) { group in
                Button(group.name) { viewModel.groups.update { $0.assign(folders, to: group.id) } }
            }
            if !viewModel.groups.state.groups.isEmpty { Divider() }
            Button(localization.L(L10n.Mods.groupNone)) { viewModel.groups.update { $0.assign(folders, to: nil) } }
            Button(localization.L(L10n.Mods.groupNew)) { listState.groupNameRequest = .create(folders: folders) }
        } label: {
            Label(localization.L(L10n.Mods.groupMoveTo), systemImage: "folder")
        }
        .help(localization.L(L10n.Mods.groupMoveTo))
        .disabled(folders.isEmpty)
    }
}

/// Le menu d'un bandeau : basculer la section (ses membres **dans le cadrage
/// courant**, règle X57 — `section.mods` en est le reflet), puis, pour un
/// groupe à soi, renommer, déplacer, supprimer.
struct ModGroupHeaderMenu: View {
    let section: ModListSectionModel
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var listState: ModListState
    @State private var confirmDelete = false

    var body: some View {
        let paused = section.mods.filter { !$0.isEnabled }
        let active = section.mods.filter(\.isEnabled)
        Menu {
            Button(localization.plural(L10n.Mods.groupEnableAll, paused.count)) {
                viewModel.toggleMods(paused, enable: true)
            }
            .disabled(paused.isEmpty)
            Button(localization.plural(L10n.Mods.groupPauseAll, active.count)) {
                viewModel.toggleMods(active, enable: false)
            }
            .disabled(active.isEmpty)
            if case .group(let id) = section.key {
                Divider()
                Button(localization.L(L10n.Mods.groupRename)) {
                    listState.groupNameRequest = .rename(id, current: section.title ?? "")
                }
                Button(localization.L(L10n.Mods.groupMoveUp)) { viewModel.groups.update { $0.move(id, by: -1) } }
                Button(localization.L(L10n.Mods.groupMoveDown)) { viewModel.groups.update { $0.move(id, by: 1) } }
                Divider()
                Button(localization.L(L10n.Mods.groupDelete), role: .destructive) { confirmDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).focusRing(cornerRadius: 4)
        .fixedSize()
        .help(localization.L(L10n.Mods.groupActions))
        .accessibilityLabel(localization.L(L10n.Mods.groupActions))
        .disabled(viewModel.bulkToggleProgress != nil)
        .confirmationDialog(localization.L(L10n.Mods.groupDelete), isPresented: $confirmDelete) {
            Button(localization.L(L10n.Mods.groupDelete), role: .destructive) {
                if case .group(let id) = section.key { viewModel.groups.update { $0.deleteGroup(id) } }
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) {}
        } message: {
            Text(localization.L(L10n.Mods.groupDeleteConfirm))
        }
    }
}

/// La feuille du nom : vide ou déjà pris, l'erreur s'affiche et la feuille
/// reste ouverte.
struct ModGroupNameSheet: View {
    let request: ModGroupNameRequest
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: ModGroupsState.NameError?

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            TextField(localization.L(L10n.Mods.groupName), text: $name)
                .onSubmit(save)
            if let error {
                Text(localization.L(error == .empty ? L10n.Mods.groupNameEmpty : L10n.Mods.groupNameTaken))
                    .font(AppDesign.Font.footnote).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(localization.L(L10n.Saves.cancel), role: .cancel) { dismiss() }
                Button(localization.L(L10n.Mods.groupSave), action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppDesign.Spacing.lg)
        .frame(minWidth: 320)
        .onAppear { if case .rename(_, let current) = request { name = current } }
    }

    private func save() {
        var failure: ModGroupsState.NameError?
        viewModel.groups.update { state in
            switch request {
            case .create(let folders):
                switch state.createGroup(named: name) {
                case .success(let id): state.assign(folders, to: id)
                case .failure(let e): failure = e
                }
            case .rename(let id, _):
                failure = state.rename(id, to: name)
            }
        }
        error = failure
        if failure == nil { dismiss() }
    }
}

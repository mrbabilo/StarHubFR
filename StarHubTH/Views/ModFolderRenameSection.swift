import SwiftUI

/// Renommer le dossier disputé par deux mods (X60).
///
/// **Ce que ça répare.** `ModItem.id` est le nom de dossier, et deux mods
/// peuvent porter le même — `X` actif et `.X` en pause sont deux dossiers
/// distincts. Ils se partagent alors tout ce que l'app indexe dessus, un
/// `ForEach` n'en rend qu'un, et un profil qui demande d'échanger leurs états
/// ne peut pas aboutir. Donner son propre nom à l'un des deux est le seul geste
/// qui supprime la cause.
///
/// La vue laisse **choisir lequel** renommer : les deux prétendants sont
/// nommés, avec leur auteur, leur identifiant et l'état de leur dossier. Sans
/// ça, l'utilisateur renommerait au hasard celui que la liste des mods lui
/// montre — c'est-à-dire, justement, celui qu'elle a choisi arbitrairement.
struct ModFolderRenameSection: View {
    @ObservedObject var vm: StarHubTHViewModel
    let folderName: String
    let onDone: () -> Void

    @State private var selectedUniqueId: String?
    @State private var newName: String = ""
    @State private var failure: String?

    /// Les mods qui réclament ce nom logique. Deux en général ; la vue tient
    /// n'en trouver qu'un (le parc a bougé depuis l'ouverture de la feuille).
    private var claimants: [ModItem] {
        vm.mods.filter { $0.folderName == folderName }
    }

    private var chosen: ModItem? {
        claimants.first { $0.uniqueId == selectedUniqueId } ?? claimants.first
    }

    private var verdict: ModFolderRename.Verdict {
        guard let chosen else { return .empty }
        return ModFolderRename.validate(newName, renaming: chosen.folderName,
                                        existing: vm.mods.map(\.folderName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(vm.L(L10n.Mods.renameTitle))
                .font(AppDesign.Font.headline)
            Text(vm.L(L10n.Mods.renameExplain))
                .font(AppDesign.Font.footnote)
                .foregroundColor(AppDesign.Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Le choix du prétendant. `uniqueId` comme identité : `folderName`
            // est justement ce qu'ils ont en commun, et l'index de position
            // ferait sauter la sélection au prochain scan.
            ForEach(claimants, id: \.uniqueId) { mod in
                Button {
                    selectedUniqueId = mod.uniqueId
                } label: {
                    HStack(spacing: AppDesign.Spacing.sm) {
                        Image(systemName: mod.uniqueId == chosen?.uniqueId
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(AppDesign.Color.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(mod.name) — \(mod.author)")
                                .font(AppDesign.Font.body)
                            Text("\(mod.uniqueId) · \(mod.physicalFolderName)")
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(AppDesign.Color.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            // Ce que le renommage ne fait **pas** suivre, et pourquoi. Sans
            // cette ligne, l'utilisateur qui a saisi un identifiant Nexus à la
            // main le chercherait ensuite sur le mod renommé.
            if claimants.count > 1 {
                note(vm.L(L10n.Mods.renameSharedNote), icon: "arrow.uturn.left")
            }
            // Un avertissement, pas une interdiction — c'est la doctrine du
            // dépôt. Renommer le dossier d'un mod **en pause** pendant que le
            // jeu tourne ne risque rien : SMAPI ne l'a pas chargé.
            if vm.isGameRunning(), chosen?.isEnabled == true {
                note(vm.L(L10n.Mods.renameGameRunning), icon: "gamecontroller.fill")
            }

            Divider()

            Text(vm.L(L10n.Mods.renameField)).font(AppDesign.Font.footnote)
            TextField("", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)

            if let message = message(for: verdict) {
                Text(message)
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(AppDesign.Color.error)
            }
            if let failure {
                Text(failure)
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(AppDesign.Color.error)
            }

            HStack {
                Spacer()
                Button(vm.L(L10n.Mods.renameConfirm)) { rename() }
                    .disabled(verdict != .ok)
            }
        }
        .onAppear {
            selectedUniqueId = claimants.first?.uniqueId
            newName = folderName
        }
    }

    private func note(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(AppDesign.Color.warning)
            Text(text)
                .font(AppDesign.Font.footnote)
                .foregroundColor(AppDesign.Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(AppDesign.Spacing.sm)
        .background(AppDesign.Color.warning.opacity(0.08))
        .cornerRadius(6)
    }

    /// Rien tant que le champ n'a pas bougé : afficher « c'est déjà son nom »
    /// à l'ouverture reprocherait à l'utilisateur de n'avoir encore rien tapé.
    private func message(for verdict: ModFolderRename.Verdict) -> String? {
        switch verdict {
        case .ok, .unchanged: return nil
        case .empty: return vm.L(L10n.Mods.renameErrorEmpty)
        case .leadingDot: return vm.L(L10n.Mods.renameErrorDot)
        case .invalidCharacter: return vm.L(L10n.Mods.renameErrorCharacter)
        case .alreadyTaken: return vm.L(L10n.Mods.renameErrorTaken)
        }
    }

    private func rename() {
        guard let chosen else { return }
        switch vm.renameModFolder(chosen, to: newName) {
        case .renamed:
            onDone()
        case .refused(let verdict):
            failure = message(for: verdict)
        case .failed(let reason):
            failure = String(format: vm.L(L10n.Mods.renameFailed), reason)
        }
    }
}
